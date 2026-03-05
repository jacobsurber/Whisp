import SwiftUI
import AppKit
import os.log

internal extension ContentView {
    func startRecording() {
        // Safety check: don't allow recording while transcription is processing
        guard !isProcessing else {
            Logger.app.warning("Cannot start recording while transcription is in progress")
            errorMessage = "Please wait for current transcription to complete"
            showError = true
            return
        }

        // Safety check: don't allow recording if already recording
        guard !audioRecorder.isRecording else {
            Logger.app.warning("Cannot start recording while already recording")
            return
        }

        if !audioRecorder.hasPermission {
            permissionManager.requestPermissionWithEducation()
            return
        }

        // If the user selected local Whisper, ensure the model download has started so recording can proceed
        // and transcription can wait on the download if needed.
        if transcriptionProvider == .local {
            startWhisperModelDownloadIfNeeded(selectedWhisperModel)
        }

        let success = audioRecorder.startRecording()
        if !success {
            errorMessage = LocalizedStrings.Errors.failedToStartRecording
            showError = true
        }
    }
    
    func stopAndProcess() {
        processingTask?.cancel()
        NotificationCenter.default.post(name: .recordingStopped, object: nil)

        let shouldHintThisRun = !hasShownFirstModelUseHint && isLocalModelInvocationPlanned()
        if shouldHintThisRun { showFirstModelUseHint = true }

        processingTask = Task {
            isProcessing = true
            transcriptionStartTime = Date()
            progressMessage = "Preparing audio..."

            // Post notification that transcription has started
            NotificationCenter.default.post(name: .transcriptionStarted, object: nil)
            
            do {
                try Task.checkCancellation()
                guard let audioURL = audioRecorder.stopRecording() else {
                    throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.failedToGetRecordingURL])
                }
                let sessionDuration = audioRecorder.lastRecordingDuration
                
                guard !audioURL.path.isEmpty else {
                    throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.recordingURLEmpty])
                }

                try Task.checkCancellation()
                
                let text: String
                if transcriptionProvider == .local {
                    try await ensureWhisperModelIsReadyForTranscription(selectedWhisperModel)
                    text = try await speechService.transcribeRaw(audioURL: audioURL, provider: transcriptionProvider, model: selectedWhisperModel)
                } else {
                    text = try await speechService.transcribeRaw(audioURL: audioURL, provider: transcriptionProvider)
                }
                
                try Task.checkCancellation()
                
                let modeRaw = UserDefaults.standard.string(forKey: AppDefaults.Keys.semanticCorrectionMode) ?? SemanticCorrectionMode.off.rawValue
                let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off
                var finalText = text
                let sourceBundleId: String? = await MainActor.run { currentSourceAppInfo().bundleIdentifier }
                if mode != .off {
                    await MainActor.run { progressMessage = "Semantic correction..." }
                    let outcome = await semanticCorrectionService.correctWithWarning(text: text, providerUsed: transcriptionProvider, sourceAppBundleId: sourceBundleId)
                    if let warning = outcome.warning {
                        await MainActor.run { progressMessage = warning }
                    }
                    let trimmed = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        finalText = outcome.text
                    }
                }
                let wordCount = UsageMetricsStore.estimatedWordCount(for: finalText)
                let characterCount = finalText.count

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)
                let shouldSave: Bool = await MainActor.run { DataManager.shared.isHistoryEnabled }
                if shouldSave {
                    let modelUsed: String? = await MainActor.run { (transcriptionProvider == .local) ? self.selectedWhisperModel.rawValue : nil }
                    let sourceInfo: SourceAppInfo = await MainActor.run { currentSourceAppInfo() }
                    let record = TranscriptionRecord(
                        text: finalText,
                        provider: transcriptionProvider,
                        duration: sessionDuration,
                        modelUsed: modelUsed,
                        wordCount: wordCount,
                        characterCount: characterCount,
                        sourceAppBundleId: sourceInfo.bundleIdentifier,
                        sourceAppName: sourceInfo.displayName,
                        sourceAppIconData: sourceInfo.iconData
                    )
                    await DataManager.shared.saveTranscriptionQuietly(record)
                }
                await MainActor.run {
                    UsageMetricsStore.shared.recordSession(
                        duration: sessionDuration,
                        wordCount: wordCount,
                        characterCount: characterCount
                    )
                    recordSourceUsage(words: wordCount, characters: characterCount)
                    transcriptionStartTime = nil
                    showConfirmationAndPaste(text: finalText)
                    if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }

                    // Post notification that transcription completed successfully
                    NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)
                }
            } catch is CancellationError {
                await MainActor.run {
                    isProcessing = false
                    transcriptionStartTime = nil
                    if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }

                    // Post notification that transcription completed (cancelled)
                    NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)
                }
            } catch {
                if case let SpeechToTextError.localTranscriptionFailed(inner) = error,
                   let lwError = inner as? LocalWhisperError,
                   lwError == .modelNotDownloaded {
                    await MainActor.run {
                        errorMessage = "Local Whisper model not downloaded. Opening Settings…"
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                } else if let pe = error as? ParakeetError, pe == .modelNotReady {
                    await MainActor.run {
                        errorMessage = "Parakeet model not downloaded. Opening Settings…"
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                } else {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                }

                // Post notification that transcription completed (error)
                await MainActor.run {
                    NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)
                }
            }
        }
    }

    func transcribeExternalAudioFile(_ audioURL: URL) {
        processingTask?.cancel()

        let shouldHintThisRun = !hasShownFirstModelUseHint && isLocalModelInvocationPlanned()
        if shouldHintThisRun { showFirstModelUseHint = true }

        processingTask = Task {
            isProcessing = true
            transcriptionStartTime = Date()
            progressMessage = "Transcribing file..."

            do {
                try Task.checkCancellation()

                let text: String
                if transcriptionProvider == .local {
                    try await ensureWhisperModelIsReadyForTranscription(selectedWhisperModel)
                    text = try await speechService.transcribeRaw(audioURL: audioURL, provider: transcriptionProvider, model: selectedWhisperModel)
                } else {
                    text = try await speechService.transcribeRaw(audioURL: audioURL, provider: transcriptionProvider)
                }

                try Task.checkCancellation()

                let modeRaw = UserDefaults.standard.string(forKey: AppDefaults.Keys.semanticCorrectionMode) ?? SemanticCorrectionMode.off.rawValue
                let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off
                var finalText = text
                let sourceBundleId: String? = await MainActor.run { currentSourceAppInfo().bundleIdentifier }
                if mode != .off {
                    await MainActor.run { progressMessage = "Semantic correction..." }
                    let outcome = await semanticCorrectionService.correctWithWarning(text: text, providerUsed: transcriptionProvider, sourceAppBundleId: sourceBundleId)
                    if let warning = outcome.warning {
                        await MainActor.run { progressMessage = warning }
                    }
                    let trimmed = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        finalText = outcome.text
                    }
                }
                let wordCount = UsageMetricsStore.estimatedWordCount(for: finalText)
                let characterCount = finalText.count

                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
                let fileSize = (fileAttributes?[.size] as? Int64) ?? 0
                let estimatedDuration = TimeInterval(fileSize) / 16000.0

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)
                let shouldSave: Bool = await MainActor.run { DataManager.shared.isHistoryEnabled }
                if shouldSave {
                    let modelUsed: String? = await MainActor.run { (transcriptionProvider == .local) ? self.selectedWhisperModel.rawValue : nil }
                    let sourceInfo: SourceAppInfo = await MainActor.run { currentSourceAppInfo() }
                    let record = TranscriptionRecord(
                        text: finalText,
                        provider: transcriptionProvider,
                        duration: estimatedDuration,
                        modelUsed: modelUsed,
                        wordCount: wordCount,
                        characterCount: characterCount,
                        sourceAppBundleId: sourceInfo.bundleIdentifier,
                        sourceAppName: sourceInfo.displayName,
                        sourceAppIconData: sourceInfo.iconData
                    )
                    await DataManager.shared.saveTranscriptionQuietly(record)
                }
                await MainActor.run {
                    UsageMetricsStore.shared.recordSession(
                        duration: estimatedDuration,
                        wordCount: wordCount,
                        characterCount: characterCount
                    )
                    recordSourceUsage(words: wordCount, characters: characterCount)
                    transcriptionStartTime = nil
                    showConfirmationAndPaste(text: finalText)
                    if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isProcessing = false
                    transcriptionStartTime = nil
                    if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }

                    // Post notification that transcription completed (cancelled)
                    NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)
                }
            } catch {
                if case let SpeechToTextError.localTranscriptionFailed(inner) = error,
                   let lwError = inner as? LocalWhisperError,
                   lwError == .modelNotDownloaded {
                    await MainActor.run {
                        errorMessage = "Local Whisper model not downloaded. Opening Settings…"
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                } else if let pe = error as? ParakeetError, pe == .modelNotReady {
                    await MainActor.run {
                        errorMessage = "Parakeet model not downloaded. Opening Settings…"
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                } else {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                }

                // Post notification that transcription completed (error)
                await MainActor.run {
                    NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)
                }
            }
        }
    }

    func showConfirmationAndPaste(text: String) {
        showSuccess = true
        isProcessing = false
        soundManager.playCompletionSound()
        
        let enableSmartPaste = UserDefaults.standard.bool(forKey: "enableSmartPaste")
        if enableSmartPaste {
            if !awaitingSemanticPaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    performUserTriggeredPaste()
                }
            }
        } else {
            NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let recordWindow = NSApp.windows.first { window in
                    window.title == "AudioWhisper Recording"
                }
                
                if let window = recordWindow {
                    window.orderOut(nil)
                } else {
                    NSApplication.shared.keyWindow?.orderOut(nil)
                }
                
                NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
                showSuccess = false
            }
        }
    }
    
    private func isLocalModelInvocationPlanned() -> Bool {
        if transcriptionProvider == .local || transcriptionProvider == .parakeet { return true }
        let modeRaw = UserDefaults.standard.string(forKey: AppDefaults.Keys.semanticCorrectionMode) ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off
        if mode == .localMLX { return true }
        return false
    }

    func startWhisperModelDownloadIfNeeded(_ model: WhisperModel) {
        guard !WhisperKitStorage.isModelDownloaded(model) else { return }
        guard !(modelManager.downloadStages[model]?.isActive ?? false) else { return }
        guard !modelManager.downloadingModels.contains(model) else { return }

        Task {
            do {
                try await modelManager.downloadModel(model)
                await modelManager.refreshModelStates()
            } catch {
                // Don't alert while recording; the transcription flow will surface errors if the model is still missing.
            }
        }
    }

    private func ensureWhisperModelIsReadyForTranscription(_ model: WhisperModel) async throws {
        if WhisperKitStorage.isModelDownloaded(model) { return }

        await MainActor.run {
            progressMessage = "Downloading \(model.displayName) model…"
        }

        do {
            try await modelManager.downloadModel(model)
            await modelManager.refreshModelStates()
        } catch let err as ModelError where err == .alreadyDownloading {
            try await waitForWhisperModelDownload(model)
        }

        if !WhisperKitStorage.isModelDownloaded(model) {
            throw LocalWhisperError.modelNotDownloaded
        }
    }

    private func waitForWhisperModelDownload(_ model: WhisperModel) async throws {
        let timeout: TimeInterval = 20 * 60 // 20 minutes
        let startedAt = Date()
        var didRetry = false

        while true {
            try Task.checkCancellation()

            if WhisperKitStorage.isModelDownloaded(model) { return }

            if Date().timeIntervalSince(startedAt) > timeout {
                throw ModelError.downloadTimeout
            }

            let stage = await MainActor.run { modelManager.downloadStages[model] }
            if let stage {
                await MainActor.run {
                    switch stage {
                    case .preparing:
                        progressMessage = "Preparing \(model.displayName) model…"
                    case .downloading:
                        progressMessage = "Downloading \(model.displayName) model…"
                    case .processing:
                        progressMessage = "Processing \(model.displayName) model…"
                    case .completing:
                        progressMessage = "Finalizing \(model.displayName) model…"
                    case .ready:
                        progressMessage = "Model ready"
                    case .failed(let message):
                        progressMessage = "Download failed: \(message)"
                    }
                }

                if case .failed(let message) = stage {
                    throw SpeechToTextError.transcriptionFailed(message)
                }
            } else {
                // Stage may be cleared after a failure; retry once.
                if !didRetry {
                    didRetry = true
                    do {
                        try await modelManager.downloadModel(model)
                        continue
                    } catch {
                        // Fall through to keep waiting/polling with best-effort messaging.
                    }
                }
                await MainActor.run {
                    progressMessage = "Downloading \(model.displayName) model…"
                }
            }

            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
