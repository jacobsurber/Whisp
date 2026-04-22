import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

internal struct DashboardPermissionsView: View {
    @State private var microphoneStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .audio)
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    @State private var isInputMonitoringGranted = InputMonitoringPermissionManager().checkPermission()
    @AppStorage(AppDefaults.Keys.enableSmartPaste) private var enableSmartPaste = true
    @AppStorage(AppDefaults.Keys.pressAndHoldEnabled) private var pressAndHoldEnabled = true
    @AppStorage(AppDefaults.Keys.pressAndHoldKeyIdentifier) private var pressAndHoldKeyIdentifier =
        PressAndHoldConfiguration.defaults.key.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnReadiness) private var pressAndHoldFnReadinessRaw =
        FnGlobeHotkeyReadiness.requiresAcknowledgement.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnFailureMessage) private var pressAndHoldFnFailureMessage = ""

    private let inputMonitoringPermissionManager = InputMonitoringPermissionManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                microphoneCard
                if needsAccessibility { accessibilityCard }
                if needsInputMonitoring { inputMonitoringCard }

                Text(
                    "Only microphone access is required to start. Accessibility and Input Monitoring are optional — needed for Smart Paste and hotkeys."
                )
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.inkMuted)
                .padding(.horizontal, 2)
            }
            .padding(DashboardTheme.Spacing.lg)
        }
        .background(DashboardTheme.pageBg)
        .onAppear(perform: refreshStatuses)
        .onChange(of: enableSmartPaste) { _, _ in refreshStatuses() }
        .onChange(of: pressAndHoldEnabled) { _, _ in refreshStatuses() }
        .onChange(of: pressAndHoldKeyIdentifier) { _, _ in refreshStatuses() }
    }

    private var microphoneCard: some View {
        SettingsSectionCard(title: "Microphone", icon: "mic") {
            permissionStatusRow(
                isGranted: microphoneStatus == .authorized,
                grantedText: "Granted",
                requiredText: microphoneStatus == .denied ? "Denied" : "Required"
            )

            SettingsDivider()

            HStack(spacing: 10) {
                Button("Grant Access") { requestMicrophonePermission() }
                    .disabled(microphoneStatus == .authorized)
                Button("Open Settings") { openSystemSettings(path: "Privacy_Microphone") }
            }
            .padding(.horizontal, DashboardTheme.Spacing.md)
            .padding(.vertical, 10)
        }
    }

    private var accessibilityCard: some View {
        SettingsSectionCard(title: "Accessibility", icon: "accessibility") {
            permissionStatusRow(
                isGranted: isAccessibilityTrusted,
                grantedText: "Granted",
                requiredText: "Required"
            )

            SettingsDivider()

            HStack(spacing: 10) {
                Button("Open Settings") { openSystemSettings(path: "Privacy_Accessibility") }
                Button("Refresh") { refreshStatuses() }
            }
            .padding(.horizontal, DashboardTheme.Spacing.md)
            .padding(.vertical, 10)

            SettingsDivider()

            Text(accessibilityFooterText)
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.inkMuted)
                .padding(.horizontal, DashboardTheme.Spacing.md)
                .padding(.vertical, 8)
        }
    }

    private var inputMonitoringCard: some View {
        SettingsSectionCard(title: "Input Monitoring", icon: "keyboard") {
            permissionStatusRow(
                isGranted: isInputMonitoringGranted,
                grantedText: "Granted",
                requiredText: "Required"
            )

            if let message = inputMonitoringStatusMessage {
                SettingsDivider()
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(DashboardTheme.inkMuted)
                    .padding(.horizontal, DashboardTheme.Spacing.md)
                    .padding(.vertical, 8)
            }

            SettingsDivider()

            HStack(spacing: 10) {
                Button("Grant Access") { refreshFnGlobePermission(requestAccess: true) }
                Button("Open Settings") { inputMonitoringPermissionManager.openSystemSettings() }
                Button("Refresh") { refreshFnGlobePermission() }
            }
            .padding(.horizontal, DashboardTheme.Spacing.md)
            .padding(.vertical, 10)

            SettingsDivider()

            Text(
                "Needed for hotkey detection. After granting access, click Refresh. If status does not update, restart Whisp."
            )
            .font(.system(size: 11))
            .foregroundStyle(DashboardTheme.inkMuted)
            .padding(.horizontal, DashboardTheme.Spacing.md)
            .padding(.vertical, 8)
        }
    }

    private func permissionStatusRow(
        isGranted: Bool, grantedText: String, requiredText: String
    ) -> some View {
        HStack(alignment: .center) {
            Text("Status")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DashboardTheme.ink)
            Spacer()
            permissionLabel(
                isGranted: isGranted,
                grantedText: grantedText,
                requiredText: requiredText
            )
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, 10)
    }

    private var currentPressAndHoldConfiguration: PressAndHoldConfiguration {
        PressAndHoldSettings.configuration()
    }

    private var selectedPressAndHoldKey: PressAndHoldKey {
        currentPressAndHoldConfiguration.key
    }

    private var needsAccessibility: Bool { enableSmartPaste }
    private var needsInputMonitoring: Bool { currentPressAndHoldConfiguration.enabled }

    private var fnGlobeReadiness: FnGlobeHotkeyReadiness {
        FnGlobeHotkeyReadiness(rawValue: pressAndHoldFnReadinessRaw) ?? .requiresAcknowledgement
    }

    private var inputMonitoringStatusMessage: String? {
        if !pressAndHoldFnFailureMessage.isEmpty { return pressAndHoldFnFailureMessage }

        if fnGlobeReadiness == .awaitingVerification {
            return
                "Hold Fn / Globe until Whisp starts recording. If macOS opens Emoji & Symbols or Dictation, set Keyboard > Press Globe key to Do Nothing and refresh this page."
        }

        return nil
    }

    private var accessibilityFooterText: String {
        "Optional. Required only for Smart Paste to type into other apps."
    }

    private func permissionLabel(
        isGranted: Bool, grantedText: String, requiredText: String
    ) -> some View {
        Label(
            isGranted ? grantedText : requiredText,
            systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(isGranted ? DashboardTheme.success : Color(nsColor: .systemOrange))
        .font(.system(size: 13, weight: .medium))
    }

    private func refreshStatuses() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        isAccessibilityTrusted = AXIsProcessTrusted()
        isInputMonitoringGranted = inputMonitoringPermissionManager.checkPermission()
    }

    private func refreshFnGlobePermission(requestAccess: Bool = false) {
        if requestAccess { _ = inputMonitoringPermissionManager.requestPermission() }
        refreshStatuses()
        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: nil)
    }

    private func requestMicrophonePermission() {
        guard !AppEnvironment.isRunningTests else { return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                microphoneStatus = granted ? .authorized : .denied
            }
        }
    }

    private func openSystemSettings(path: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    DashboardPermissionsView()
        .frame(width: 900, height: 700)
}
