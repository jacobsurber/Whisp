import Foundation
import SwiftUI
import os.log

/// Coordinates transcription processing independently of UI.
/// Handles audio transcription, semantic correction, history saving, and smart paste.
/// This service can be called from anywhere (AppDelegate, ContentView, Dashboard)
/// without needing a view or window.
@MainActor
internal final class TranscriptionCoordinator {
    static let shared = TranscriptionCoordinator()
    static let minimumRecordingDuration: TimeInterval = 0.35

    // Progress callback for UI updates (optional)
    var progressHandler: ((String) -> Void)?

    private let speechService: SpeechToTextService
    private let semanticCorrectionService = SemanticCorrectionService()
    private let pasteManager = PasteManager()

    private init() {
        self.speechService = SpeechToTextService()
    }

    /// Process a recorded audio file: transcribe, apply semantic correction, save history, and optionally paste
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - sessionDuration: Duration of the recording session
    ///   - provider: Transcription provider to use (default: from UserDefaults)
    ///   - selectedModel: WhisperModel if using local provider (default: from UserDefaults)
    ///   - sourceAppInfo: Info about the source app for history tracking
    ///   - automate: Whether to automatically paste the result (Smart Paste)
    /// - Returns: The final transcribed and corrected text
    func processRecording(
        audioURL: URL,
        sessionDuration: TimeInterval?,
        provider: TranscriptionProvider? = nil,
        selectedModel: WhisperModel? = nil,
        sourceAppInfo: SourceAppInfo? = nil,
        shouldPaste: Bool = true
    ) async throws -> String {
        // Ensure temp file cleanup on all exit paths (success or error)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        if let sessionDuration, sessionDuration < Self.minimumRecordingDuration {
            throw SpeechToTextError.recordingTooShort
        }

        progressHandler?("Preparing audio...")

        // Get provider from UserDefaults if not specified
        let transcriptionProvider: TranscriptionProvider
        if let provider = provider {
            transcriptionProvider = provider
        } else {
            let storedProvider = UserDefaults.standard.string(forKey: AppDefaults.Keys.transcriptionProvider)
            transcriptionProvider =
                storedProvider.flatMap { TranscriptionProvider(rawValue: $0) }
                ?? AppDefaults.defaultTranscriptionProvider
        }

        // Get model from UserDefaults if not specified
        let whisperModel: WhisperModel
        if let selectedModel = selectedModel {
            whisperModel = selectedModel
        } else {
            let storedModel = UserDefaults.standard.string(forKey: AppDefaults.Keys.selectedWhisperModel)
            whisperModel =
                storedModel.flatMap { WhisperModel(rawValue: $0) } ?? AppDefaults.defaultWhisperModel
        }

        // Transcribe audio
        let text: String
        if transcriptionProvider == .local {
            // Ensure model is downloaded before transcription
            try await ensureWhisperModelIsReady(whisperModel)
            text = try await speechService.transcribeRaw(
                audioURL: audioURL, provider: transcriptionProvider, model: whisperModel)
        } else {
            text = try await speechService.transcribeRaw(audioURL: audioURL, provider: transcriptionProvider)
        }

        try Task.checkCancellation()

        // Get semantic correction mode
        let modeRaw =
            UserDefaults.standard.string(forKey: AppDefaults.Keys.semanticCorrectionMode)
            ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off

        // Apply semantic correction if enabled (skip for Gemma — it combines transcription + correction)
        var finalText = text
        let sourceBundleId = sourceAppInfo?.bundleIdentifier
        if mode != .off && transcriptionProvider != .gemma {
            progressHandler?("Semantic correction...")
            let outcome = await semanticCorrectionService.correctWithWarning(
                text: text,
                providerUsed: transcriptionProvider,
                sourceAppBundleId: sourceBundleId
            )
            if let warning = outcome.warning {
                progressHandler?(warning)
            }
            let trimmed = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                finalText = outcome.text
            }
        } else if mode != .off && transcriptionProvider == .gemma {
            finalText = semanticCorrectionService.canonicalizeUsingPersonalDictionaryIfEnabled(
                text,
                mode: mode
            )
        }

        try Task.checkCancellation()

        // Calculate metrics
        let wordCount = UsageMetricsStore.estimatedWordCount(for: finalText)
        let characterCount = finalText.count

        // Save to transcript history
        let record = TranscriptionRecord(
            text: finalText,
            provider: transcriptionProvider,
            duration: sessionDuration,
            modelUsed: transcriptionProvider == .local ? whisperModel.rawValue : nil,
            wordCount: wordCount,
            characterCount: characterCount,
            sourceAppBundleId: sourceAppInfo?.bundleIdentifier,
            sourceAppName: sourceAppInfo?.displayName,
            sourceAppIconData: sourceAppInfo?.iconData
        )
        await DataManager.shared.saveTranscriptionQuietly(record)

        // Record usage metrics
        if let duration = sessionDuration {
            UsageMetricsStore.shared.recordSession(
                duration: duration,
                wordCount: wordCount,
                characterCount: characterCount
            )
        }

        // Record source app usage
        recordSourceUsage(words: wordCount, characters: characterCount, sourceInfo: sourceAppInfo)

        // Type directly into the focused app (bypasses clipboard entirely)
        if shouldPaste {
            let enableSmartPaste = UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableSmartPaste)
            Logger.app.debug("SmartPaste enabled=\(enableSmartPaste)")
            if enableSmartPaste {
                try? await Task.sleep(for: .milliseconds(100))
                let didType = pasteManager.typeToActiveApp(text: finalText)
                Logger.app.debug("SmartPaste type result=\(didType)")

                if !didType {
                    await showPasteFailureAlert()
                }
            }
        }

        Logger.app.info("Transcription completed: \(wordCount) words, \(characterCount) characters")

        return finalText
    }

    // MARK: - Helper Methods

    private func ensureWhisperModelIsReady(_ model: WhisperModel) async throws {
        if WhisperKitStorage.isModelDownloaded(model) {
            return
        }

        progressHandler?("Downloading \(model.displayName) model...")

        do {
            try await ModelManager.shared.downloadModel(model)
            await ModelManager.shared.refreshModelStates()
        } catch let err as ModelError where err == .alreadyDownloading {
            // Model is already downloading, wait for it
            try await waitForWhisperModelDownload(model)
        }

        if !WhisperKitStorage.isModelDownloaded(model) {
            throw LocalWhisperError.modelNotDownloaded
        }
    }

    private func waitForWhisperModelDownload(_ model: WhisperModel) async throws {
        let timeout: TimeInterval = 20 * 60  // 20 minutes
        let startedAt = Date()
        var didRetry = false

        while true {
            try Task.checkCancellation()

            if WhisperKitStorage.isModelDownloaded(model) {
                return
            }

            if Date().timeIntervalSince(startedAt) > timeout {
                throw ModelError.downloadTimeout
            }

            let stage = ModelManager.shared.downloadStages[model]
            if let stage {
                switch stage {
                case .preparing:
                    progressHandler?("Preparing \(model.displayName) model...")
                case .downloading:
                    progressHandler?("Downloading \(model.displayName) model...")
                case .processing:
                    progressHandler?("Processing \(model.displayName) model...")
                case .completing:
                    progressHandler?("Finalizing \(model.displayName) model...")
                case .ready:
                    progressHandler?("Model ready")
                case .failed(let message):
                    throw SpeechToTextError.transcriptionFailed(message)
                }
            } else {
                // Stage may be cleared after a failure; retry once
                if !didRetry {
                    didRetry = true
                    do {
                        try await ModelManager.shared.downloadModel(model)
                        continue
                    } catch {
                        // Fall through to keep waiting/polling
                    }
                }
                progressHandler?("Downloading \(model.displayName) model...")
            }

            try await Task.sleep(for: .milliseconds(250))
        }
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

    private func showPasteFailureAlert() async {
        guard !AppEnvironment.isRunningTests else { return }

        let alert = NSAlert()
        alert.messageText = "Smart Paste Requires Accessibility Permission"
        alert.informativeText =
            "Whisp needs Accessibility permission to type text into other apps. Your transcription has been copied to the clipboard.\n\nTo enable Smart Paste:\n1. Open System Settings > Privacy & Security > Accessibility\n2. Add Whisp and toggle it ON"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func recordSourceUsage(words: Int, characters: Int, sourceInfo: SourceAppInfo?) {
        guard let sourceInfo = sourceInfo else { return }

        // bundleIdentifier is non-optional in SourceAppInfo
        let bundleId = sourceInfo.bundleIdentifier

        // Record usage by source app
        let key = "sourceAppUsage_\(bundleId)"
        var usage = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        usage["words"] = (usage["words"] ?? 0) + words
        usage["characters"] = (usage["characters"] ?? 0) + characters
        usage["sessions"] = (usage["sessions"] ?? 0) + 1
        UserDefaults.standard.set(usage, forKey: key)
    }
}
