import AppKit

@MainActor
internal class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var audioRecorder: AudioRecorder?
    var recordingAnimationTimer: DispatchSourceTimer?
    var pressAndHoldMonitor: PressAndHoldKeyMonitor?
    var fnGlobeMonitor: FnGlobeMonitor?
    var pressAndHoldConfiguration = PressAndHoldSettings.configuration()
    var pressAndHoldTriggerState = PressAndHoldTriggerState()
    var dashboardWindowPresenter: DashboardWindowPresenting = DashboardWindowManager.shared
}
