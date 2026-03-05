import AppKit
import os.log
import SwiftData
import SwiftUI

internal extension AppDelegate {
    @objc func toggleRecordWindow() {
        if recordingWindow == nil {
            createRecordingWindow()
        }
        windowController.toggleRecordWindow(recordingWindow)
    }

    func showRecordingWindowForProcessing(completion: (() -> Void)? = nil) {
        if recordingWindow == nil {
            createRecordingWindow()
        }

        guard let window = recordingWindow else {
            completion?()
            return
        }

        if window.isVisible {
            completion?()
        } else {
            windowController.toggleRecordWindow(window) {
                completion?()
            }
        }
    }

    func createRecordingWindow(hidden: Bool = false) {
        guard let recorder = audioRecorder else {
            Logger.app.error("Cannot create recording window: AudioRecorder not initialized")
            return
        }

        let windowSize = LayoutMetrics.RecordingWindow.size
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.title = "AudioWhisper Recording"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary, .fullScreenAuxiliary]
        window.hasShadow = true
        window.isOpaque = false

        // Use DataManager's container, or fallback to in-memory, or nil (history disabled)
        let modelContainer = DataManager.shared.sharedModelContainer ?? createFallbackModelContainer()
        let contentView = ContentView(audioRecorder: recorder)
        if let modelContainer = modelContainer {
            window.contentView = NSHostingView(rootView: contentView.modelContainer(modelContainer))
        } else {
            // History disabled - continue without model container
            window.contentView = NSHostingView(rootView: contentView)
        }

        window.center()

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        recordingWindowDelegate = RecordingWindowDelegate { [weak self] in
            self?.onRecordingWindowClosed()
        }
        window.delegate = recordingWindowDelegate

        recordingWindow = window

        // Keep window hidden for background recording mode
        if !hidden {
            Logger.app.debug("Recording window created in visible mode")
        } else {
            Logger.app.debug("Recording window created in hidden mode (background processing)")
        }
    }

    private func onRecordingWindowClosed() {
        recordingWindow = nil
        recordingWindowDelegate = nil
        Logger.app.info("Recording window closed and references cleaned up")
    }

    private func createFallbackModelContainer() -> ModelContainer? {
        do {
            let schema = Schema([TranscriptionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Critical error but don't crash - transcription history will be disabled
            Logger.app.critical("Failed to create fallback ModelContainer: \(error)")

            // Show alert to user (only once per session)
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Database Error"
                alert.informativeText = "VoiceFlow couldn't initialize the transcription history database. History will be disabled this session."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }

            return nil
        }
    }

    @objc func restoreFocusToPreviousApp() {
        windowController.restoreFocusToPreviousApp()
    }
}
