import AppKit

@MainActor
internal class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var audioRecorder: AudioRecorder?
    var recordingAnimationTimer: DispatchSourceTimer?
    var pressAndHoldMonitor: PressAndHoldKeyMonitor?
    var pressAndHoldConfiguration = PressAndHoldSettings.configuration()
    var isHoldRecordingActive = false
}
