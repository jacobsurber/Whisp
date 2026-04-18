import AppKit
import ApplicationServices
import os.log

extension AppDelegate {
    private enum RecordingTriggerOrigin {
        case shortcut(PressAndHoldMode)
        case dock
    }

    func configureShortcutMonitors() {
        stopShortcutMonitors()

        if audioRecorder?.isRecording == true {
            // Keep the current hold state so an active recording can still be released normally.
        } else if pressAndHoldTriggerState.isStartPending {
            // Treat reconfiguration during async startup as a release request so the startup task
            // cancels cleanly instead of orphaning a half-started press-and-hold session.
            _ = pressAndHoldTriggerState.handleKeyUp()
        } else {
            pressAndHoldTriggerState.reset()
        }

        let newConfiguration = PressAndHoldSettings.configuration()
        pressAndHoldConfiguration = newConfiguration

        guard newConfiguration.enabled else { return }

        if newConfiguration.isFnGlobeEnabled {
            configureFnGlobeMonitor(for: newConfiguration)
            return
        }

        let inputMonitoringPermissionManager = InputMonitoringPermissionManager()
        let inputMonitoringGranted = inputMonitoringPermissionManager.checkPermission()

        PressAndHoldHotkeyPreferenceStore.syncForConfiguration(
            newConfiguration,
            inputMonitoringGranted: inputMonitoringGranted
        )

        guard inputMonitoringGranted else {
            Logger.app.info(
                "Press-and-hold monitor not started because Input Monitoring permission is not granted. Whisp will keep the floating dock available and wait for explicit permission setup."
            )
            return
        }

        let monitor = PressAndHoldKeyMonitor(
            configuration: newConfiguration,
            keyDownHandler: { [weak self] in
                self?.handlePressAndHoldKeyDown()
            },
            keyUpHandler: pressAndHoldKeyUpHandler(for: newConfiguration),
            readinessHandler: { readiness, message in
                PressAndHoldHotkeyPreferenceStore.setReadiness(readiness, message: message)
            },
            inputMonitoringPermissionManager: inputMonitoringPermissionManager
        )

        pressAndHoldMonitor = monitor
        if !monitor.start() {
            Logger.app.info(
                "Press-and-hold monitor failed to start. Check Input Monitoring permissions."
            )
        }
    }

    private func configureFnGlobeMonitor(for configuration: PressAndHoldConfiguration) {
        let inputMonitoringPermissionManager = InputMonitoringPermissionManager()
        let inputMonitoringGranted = inputMonitoringPermissionManager.checkPermission()

        FnGlobeHotkeyPreferenceStore.syncForConfiguration(
            configuration,
            inputMonitoringGranted: inputMonitoringGranted
        )

        guard FnGlobeHotkeyPreferenceStore.warningAcknowledged(), inputMonitoringGranted else { return }

        let monitor = FnGlobeMonitor(
            keyDownHandler: { [weak self] in
                self?.handlePressAndHoldKeyDown()
            },
            keyUpHandler: pressAndHoldKeyUpHandler(for: configuration),
            mode: configuration.mode,
            readinessHandler: { readiness, message in
                FnGlobeHotkeyPreferenceStore.setReadiness(readiness, message: message)
            },
            inputMonitoringPermissionManager: inputMonitoringPermissionManager
        )

        fnGlobeMonitor = monitor
        _ = monitor.start()
    }

    private func stopShortcutMonitors() {
        pressAndHoldMonitor?.stop()
        pressAndHoldMonitor = nil
        fnGlobeMonitor?.stop()
        fnGlobeMonitor = nil
    }

    private func pressAndHoldKeyUpHandler(for configuration: PressAndHoldConfiguration) -> (() -> Void)? {
        guard configuration.mode == .hold else { return nil }

        return { [weak self] in
            self?.handlePressAndHoldKeyUp()
        }
    }

    private func handlePressAndHoldKeyDown() {
        switch pressAndHoldConfiguration.mode {
        case .hold:
            startRecordingFromPressAndHold(origin: .shortcut(.hold))
        case .toggle:
            if audioRecorder?.isRecording == true {
                stopRecordingFromPressAndHold()
            } else {
                startRecordingFromPressAndHold(origin: .shortcut(.toggle))
            }
        }
    }

    private func handlePressAndHoldKeyUp() {
        guard pressAndHoldConfiguration.mode == .hold else { return }
        stopRecordingFromPressAndHold()
    }

    func handleFloatingMicrophoneDockPrimaryAction() {
        if audioRecorder?.isRecording == true {
            stopRecordingFromPressAndHold()
        } else {
            startRecordingFromPressAndHold(origin: .dock)
        }
    }

    func cancelFloatingMicrophoneDockRecording() {
        guard let recorder = audioRecorder else { return }

        pressAndHoldTriggerState.reset()
        FloatingMicrophoneDockManager.shared.resetInteractionState()

        if recorder.isRecording {
            recorder.cancelRecording()
        }

        resetToIdleState()
    }

    func showFloatingMicrophoneDockSettings() {
        let selectedNav: DashboardNavItem = (audioRecorder?.hasPermission == true) ? .recording : .permissions
        DashboardWindowManager.shared.showDashboardWindow(selectedNav: selectedNav)
    }

    private func startRecordingFromPressAndHold(origin: RecordingTriggerOrigin) {
        guard let recorder = audioRecorder else { return }

        switch pressAndHoldTriggerState.handleKeyDown(
            recorderIsRecording: recorder.isRecording
        ) {
        case .ignore:
            return
        case .keepExistingRecording:
            return
        case .beginAsyncStart:
            break
        }

        switch origin {
        case .shortcut(let mode):
            FloatingMicrophoneDockManager.shared.prepareForShortcutActivation(mode: mode)
        case .dock:
            FloatingMicrophoneDockManager.shared.prepareForDockActivation()
        }

        Task { @MainActor in
            let success = await recorder.startRecording()

            switch pressAndHoldTriggerState.handleStartCompletion(success: success) {
            case .recordingStarted:
                updateMenuBarIcon(isRecording: true)
                SoundManager().playRecordingStartSound()
            case .cancelStartedRecording:
                recorder.cancelRecording()
                FloatingMicrophoneDockManager.shared.resetInteractionState()
                resetToIdleState()
            case .startFailed:
                FloatingMicrophoneDockManager.shared.handleRecordingStartFailed()
                Logger.app.warning("Failed to start recording from press-and-hold")
            case .noOp:
                break
            }
        }
    }

    private func stopRecordingFromPressAndHold() {
        Logger.app.debug("stopRecordingFromPressAndHold called")

        switch pressAndHoldTriggerState.handleKeyUp() {
        case .ignore:
            Logger.app.debug("Not active, returning")
            return
        case .awaitPendingStart:
            Logger.app.debug("Recording start still pending, waiting for startup task")
            return
        case .stopRecording:
            break
        }

        guard let recorder = audioRecorder else {
            Logger.app.error("No audioRecorder available")
            pressAndHoldTriggerState.reset()
            FloatingMicrophoneDockManager.shared.resetInteractionState()
            return
        }

        guard recorder.isRecording else {
            Logger.app.error("Recorder not recording")
            pressAndHoldTriggerState.reset()
            FloatingMicrophoneDockManager.shared.resetInteractionState()
            return
        }

        Logger.app.debug("Starting stop sequence...")

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
                NotificationCenter.default.post(
                    name: .transcriptionFailed,
                    object: "Could not finish recording."
                )
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
                coordinator.progressHandler = { message in
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

                if let speechError = error as? SpeechToTextError,
                    case .noSpeechDetected = speechError
                {
                    SoundManager().playNoSpeechSound()
                }

                // Reset menu bar to idle state even on error
                resetToIdleState()

                // Post the failure separately so the dock can show the error instead of a success state.
                NotificationCenter.default.post(
                    name: .transcriptionFailed,
                    object: error.localizedDescription
                )

                // Show error alert (user-visible)
                DispatchQueue.main.async {
                    ErrorPresenter.shared.showError("Transcription failed: \(error.localizedDescription)")
                }
            }
        }

        Logger.app.debug("stopRecordingFromPressAndHold completed")
    }

    private func currentSourceAppInfo() -> SourceAppInfo {
        // Get the frontmost app that's not Whisp
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
            frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier
        {
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
        let indigoImage = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")?
            .withSymbolConfiguration(config)
        indigoImage?.isTemplate = false
        let indigoOutlineImage = indigoImage?.tinted(with: indigoColor)

        // Create dimmed version for pulse effect
        let dimmedIndigoColor = NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.5)
        let dimmedImage = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")?
            .withSymbolConfiguration(config)
        dimmedImage?.isTemplate = false
        let dimmedOutlineImage = dimmedImage?.tinted(with: dimmedIndigoColor)

        button.image = indigoOutlineImage

        var isPulseState = true

        let queue = DispatchQueue(label: "com.whisp.animation", qos: .background)
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

        let queue = DispatchQueue(label: "com.whisp.processing-animation", qos: .background)
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
