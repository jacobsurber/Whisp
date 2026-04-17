import AVFoundation
import AppKit
import os.log

internal class PermissionChecker {

    /// Passive startup check. Whisp no longer triggers system permission dialogs on launch.
    static func checkAndPromptForPermissions() {
        let configuration = PressAndHoldSettings.configuration()
        let needsInputMonitoring = configuration.requiresInputMonitoringPermission(
            warningAcknowledged: FnGlobeHotkeyPreferenceStore.warningAcknowledged()
        )
        let needsAccessibility =
            UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableSmartPaste)

        if needsInputMonitoring {
            let inputMonitoringPermissionManager = InputMonitoringPermissionManager()
            _ = inputMonitoringPermissionManager.checkPermission()
        }

        guard needsAccessibility else { return }
        _ = AXIsProcessTrusted()
    }

    /// Request microphone permission explicitly
    static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Check if accessibility permission is granted
    static func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
}
