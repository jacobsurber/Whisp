import AppKit

internal extension AppDelegate {
    func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onRecordingStopped),
            name: .recordingStopped,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onTranscriptionStarted),
            name: .transcriptionStarted,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onTranscriptionCompleted),
            name: .transcriptionCompleted,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onTranscriptionCompleted),
            name: .transcriptionFailed,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onPressAndHoldSettingsChanged(_:)),
            name: .pressAndHoldSettingsChanged,
            object: nil
        )
    }

    @objc private func onPressAndHoldSettingsChanged(_ notification: Notification) {
        configureShortcutMonitors()
    }
}
