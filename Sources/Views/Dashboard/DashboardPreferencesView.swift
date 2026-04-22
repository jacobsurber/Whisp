import ServiceManagement
import SwiftUI
import os.log

internal struct DashboardPreferencesView: View {
    @AppStorage(AppDefaults.Keys.startAtLogin) private var startAtLogin = true
    @AppStorage(AppDefaults.Keys.floatingMicrophoneDockEnabled) private var floatingMicrophoneDockEnabled =
        true
    @AppStorage("autoBoostMicrophoneVolume") private var autoBoostMicrophoneVolume = false
    @AppStorage(AppDefaults.Keys.enableSmartPaste) private var enableSmartPaste = true
    @AppStorage(AppDefaults.Keys.playCompletionSound) private var playCompletionSound = true
    @AppStorage(AppDefaults.Keys.maxModelStorageGB) private var maxModelStorageGB = 5.0

    @State private var loginItemError: String?

    private let storageOptions: [Double] = [1, 2, 5, 10, 20]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                SettingsSectionCard(title: "General", icon: "gearshape") {
                    SettingsToggleRow(
                        title: "Start at Login",
                        subtitle: "Launch Whisp automatically when you sign in",
                        isOn: $startAtLogin
                    )
                    .onChange(of: startAtLogin) { _, newValue in
                        updateLoginItem(enabled: newValue)
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Floating Microphone Dock",
                        subtitle: "Show a floating mic button across all apps",
                        isOn: $floatingMicrophoneDockEnabled
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Auto-Boost Microphone",
                        subtitle: "Boost mic volume while recording",
                        isOn: $autoBoostMicrophoneVolume
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Smart Paste",
                        subtitle: "Paste transcription into the active app",
                        isOn: $enableSmartPaste
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Completion Sound",
                        subtitle: "Play a sound when transcription is ready",
                        isOn: $playCompletionSound
                    )

                    if let loginItemError {
                        SettingsDivider()
                        Text(loginItemError)
                            .font(.system(size: 12))
                            .foregroundStyle(DashboardTheme.destructive)
                            .padding(.horizontal, DashboardTheme.Spacing.md)
                            .padding(.vertical, 10)
                    }
                }

                SettingsSectionCard(title: "Model Storage", icon: "internaldrive") {
                    SettingsPickerRow(
                        title: "Storage Limit",
                        subtitle: "Maximum disk space for downloaded models",
                        selection: $maxModelStorageGB,
                        options: storageOptions,
                        display: { "\(Int($0)) GB" }
                    )
                }

                SettingsSectionCard(title: "About", icon: "info.circle") {
                    SettingsLabelValueRow(
                        label: "Version",
                        value: VersionInfo.fullVersionInfo,
                        isMono: true
                    )

                    if VersionInfo.gitHash != "dev-build" && VersionInfo.gitHash != "unknown" {
                        SettingsDivider()
                        SettingsLabelValueRow(
                            label: "Git",
                            value: VersionInfo.gitHash,
                            isMono: true
                        )
                    }

                    if !VersionInfo.buildDate.isEmpty {
                        SettingsDivider()
                        SettingsLabelValueRow(
                            label: "Built",
                            value: VersionInfo.buildDate,
                            isMono: true
                        )
                    }
                }
            }
            .padding(DashboardTheme.Spacing.lg)
        }
        .background(DashboardTheme.pageBg)
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            Logger.settings.error("Failed to update login item: \(error.localizedDescription)")
            loginItemError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DashboardPreferencesView()
        .frame(width: 900, height: 700)
}
