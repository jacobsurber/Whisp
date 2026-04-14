import AppKit
import os.log

internal extension AppDelegate {
    func configureShortcutMonitors() {
        pressAndHoldMonitor?.stop()
        pressAndHoldMonitor = nil
        isHoldRecordingActive = false

        let newConfiguration = PressAndHoldSettings.configuration()
        pressAndHoldConfiguration = newConfiguration

        guard newConfiguration.enabled else { return }

        let keyUpHandler: (() -> Void)? = (newConfiguration.mode == .hold) ? { [weak self] in
            self?.handlePressAndHoldKeyUp()
        } : nil

        let monitor = PressAndHoldKeyMonitor(
            configuration: newConfiguration,
            keyDownHandler: { [weak self] in
                self?.handlePressAndHoldKeyDown()
            },
            keyUpHandler: keyUpHandler
        )

        pressAndHoldMonitor = monitor
        monitor.start()
    }

    private func handlePressAndHoldKeyDown() {
        switch pressAndHoldConfiguration.mode {
        case .hold:
            startRecordingFromPressAndHold()
        case .toggle:
            if audioRecorder?.isRecording == true {
                stopRecordingFromPressAndHold()
            } else {
                startRecordingFromPressAndHold()
            }
        }
    }

    private func handlePressAndHoldKeyUp() {
        guard pressAndHoldConfiguration.mode == .hold else { return }
        stopRecordingFromPressAndHold()
    }

    private func startRecordingFromPressAndHold() {
        guard let recorder = audioRecorder else { return }

        if recorder.isRecording {
            isHoldRecordingActive = true
            return
        }

        if !recorder.hasPermission {
            return
        }

        Task { @MainActor in
            let success = await recorder.startRecording()
            if success {
                isHoldRecordingActive = true
                updateMenuBarIcon(isRecording: true)
                SoundManager().playRecordingStartSound()
            } else {
                isHoldRecordingActive = false
                // Silent failure - just don't start recording
                Logger.app.warning("Failed to start recording from press-and-hold")
            }
        }
    }

    private func stopRecordingFromPressAndHold() {
        Logger.app.debug("stopRecordingFromPressAndHold called")

        guard isHoldRecordingActive else {
            Logger.app.debug("Not active, returning")
            return
        }

        guard let recorder = audioRecorder else {
            Logger.app.error("No audioRecorder available")
            isHoldRecordingActive = false
            return
        }

        guard recorder.isRecording else {
            Logger.app.error("Recorder not recording")
            isHoldRecordingActive = false
            return
        }

        Logger.app.debug("Starting stop sequence...")
        isHoldRecordingActive = false

        // Keep recording animation running during transcription
        // (icon will reset to idle when transcription completes)

        // Post notification that recording stopped
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
        NotificationCenter.default.post(name: .transcriptionStarted, object: nil)

        Logger.app.debug("About to stop recording...")

        // Get audio URL from recorder (async to avoid blocking main thread)
        Task { @MainActor in
            guard let audioURL = await recorder.stopRecording() else {
                Logger.app.error("Failed to get audio URL from recorder")
                resetToIdleState()
                return
            }

            Logger.app.debug("Got audio URL: \(audioURL.path)")
            let sessionDuration = recorder.lastRecordingDuration
            Logger.app.debug("Session duration: \(sessionDuration ?? 0)")

            // Get source app info for history tracking
            let sourceAppInfo = currentSourceAppInfo()
            Logger.app.debug("Source app: \(sourceAppInfo.displayName)")

            // Process transcription directly - NO window needed!
            Logger.app.debug("Creating transcription task...")
            do {
                Logger.app.debug("Inside transcription task")
                let coordinator = TranscriptionCoordinator.shared

                // Set progress handler to update menu bar (optional)
                coordinator.progressHandler = { [weak self] message in
                    Logger.app.debug("Transcription progress: \(message)")
                }

                Logger.app.debug("Calling processRecording...")
                let text = try await coordinator.processRecording(
                    audioURL: audioURL,
                    sessionDuration: sessionDuration,
                    sourceAppInfo: sourceAppInfo,
                    shouldPaste: true  // Auto-paste if Smart Paste enabled
                )

                Logger.app.debug("Transcription completed, playing sound...")
                // Play completion sound
                SoundManager().playCompletionSound()

                // Reset menu bar to idle state
                resetToIdleState()

                // Post notification that transcription completed
                NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)

                Logger.app.info("Background transcription completed: \(text.prefix(50))...")
            } catch {
                Logger.app.error("Transcription failed: \(error.localizedDescription)")

                // Reset menu bar to idle state even on error
                resetToIdleState()

                // Post notification that transcription completed (with error)
                NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)

                // Show error alert (user-visible)
                DispatchQueue.main.async {
                    ErrorPresenter.shared.showError("Transcription failed: \(error.localizedDescription)")
                }
            }
        }

        Logger.app.debug("stopRecordingFromPressAndHold completed")
    }

    private func currentSourceAppInfo() -> SourceAppInfo {
        // Get the frontmost app that's not VoiceFlow
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            return SourceAppInfo.from(app: frontmostApp) ?? SourceAppInfo.unknown
        }

        // Fallback to runningApplications
        let apps = NSWorkspace.shared.runningApplications
        for app in apps where app.isActive && app.bundleIdentifier != Bundle.main.bundleIdentifier {
            return SourceAppInfo.from(app: app) ?? SourceAppInfo.unknown
        }

        return SourceAppInfo.unknown
    }

    private func updateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }

        if isRecording {
            startRecordingAnimation()
        } else {
            stopRecordingAnimation()
            button.image = AppSetupHelper.createMenuBarIcon()
        }
    }

    private func startRecordingAnimation() {
        guard let button = statusItem?.button else {
            Logger.app.error("Cannot start recording animation: button is nil")
            return
        }

        stopRecordingAnimation()

        let iconSize = AppSetupHelper.getAdaptiveMenuBarIconSize()
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)

        // WhisperFlow-inspired indigo/purple color (#6466F1)
        let indigoColor = NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1.0)

        // Create indigo tinted image
        let indigoImage = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
        indigoImage?.isTemplate = false
        let indigoOutlineImage = indigoImage?.tinted(with: indigoColor)

        // Create dimmed version for pulse effect
        let dimmedIndigoColor = NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.5)
        let dimmedImage = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
        dimmedImage?.isTemplate = false
        let dimmedOutlineImage = dimmedImage?.tinted(with: dimmedIndigoColor)

        button.image = indigoOutlineImage

        var isPulseState = true

        let queue = DispatchQueue(label: "com.voiceflow.animation", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: queue)

        // WhisperFlow-inspired 400ms animation cycle
        timer.schedule(deadline: .now(), repeating: 0.4)

        timer.setEventHandler { [weak self] in
            // Access button through statusItem to ensure it's always current
            guard let strongSelf = self, let currentButton = strongSelf.statusItem?.button else { return }

            isPulseState.toggle()

            Task { @MainActor in
                currentButton.image = isPulseState ? indigoOutlineImage : dimmedOutlineImage
            }
        }

        recordingAnimationTimer = timer
        timer.resume()
    }

    private func stopRecordingAnimation() {
        recordingAnimationTimer?.cancel()
        recordingAnimationTimer = nil
    }

    private func startProcessingAnimation() {
        guard let button = statusItem?.button else { return }

        stopRecordingAnimation()

        let iconSize = AppSetupHelper.getAdaptiveMenuBarIconSize()
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)

        let orangeColor = NSColor.systemOrange

        // Rotating between two icons to show "working" state
        let icon1 = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Processing")?
            .withSymbolConfiguration(config)
        icon1?.isTemplate = false
        let tinted1 = icon1?.tinted(with: orangeColor)

        let dimmedColor = orangeColor.withAlphaComponent(0.4)
        let icon2 = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Processing")?
            .withSymbolConfiguration(config)
        icon2?.isTemplate = false
        let tinted2 = icon2?.tinted(with: dimmedColor)

        button.image = tinted1

        var isPulseState = true

        let queue = DispatchQueue(label: "com.voiceflow.processing-animation", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.6)

        timer.setEventHandler { [weak self] in
            guard let strongSelf = self, let currentButton = strongSelf.statusItem?.button else { return }
            isPulseState.toggle()
            Task { @MainActor in
                currentButton.image = isPulseState ? tinted1 : tinted2
            }
        }

        recordingAnimationTimer = timer
        timer.resume()
    }

    @objc func onRecordingStopped() {
        updateMenuBarIcon(isRecording: false)
    }

    @objc func onTranscriptionStarted() {
        // Switch from recording pulse to processing animation
        startProcessingAnimation()
    }

    @objc func onTranscriptionCompleted() {
        resetToIdleState()
    }

    private func resetToIdleState() {
        stopRecordingAnimation()

        // Ensure statusItem exists
        if statusItem == nil {
            Logger.app.error("statusItem is nil! Recreating...")
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        guard let button = statusItem?.button else {
            Logger.app.error("Cannot reset to idle state: statusItem.button is nil even after recreation")
            return
        }

        button.image = AppSetupHelper.createMenuBarIcon()
        button.title = ""
        Logger.app.debug("Menu bar reset to idle state")
    }
}
