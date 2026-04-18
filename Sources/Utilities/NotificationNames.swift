import Foundation

// MARK: - Typed Notification Names

internal extension Notification.Name {
    // MARK: - Settings and Configuration
    static let pressAndHoldSettingsChanged = Notification.Name("PressAndHoldSettingsChanged")

    // MARK: - Recording Events
    static let recordingStopped = Notification.Name("RecordingStopped")
    static let transcriptionStarted = Notification.Name("TranscriptionStarted")
    static let transcriptionCompleted = Notification.Name("TranscriptionCompleted")
    static let transcriptionFailed = Notification.Name("TranscriptionFailed")
}
