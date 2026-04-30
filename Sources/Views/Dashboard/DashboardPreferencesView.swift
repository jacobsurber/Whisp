import AVFoundation
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
    @AppStorage("selectedMicrophone") private var selectedMicrophone = ""
    @AppStorage(AppDefaults.Keys.showDockIcon) private var showDockIcon = false
    @AppStorage(AppDefaults.Keys.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(AppDefaults.Keys.showDockTooltip) private var showDockTooltip = true

    @State private var loginItemError: String?
    @State private var availableMicrophones: [AVCaptureDevice] = []

    private let storageOptions: [Double] = [1, 2, 5, 10, 20]

    var body: some View {
        Form {
            Section("Microphone") {
                if availableMicrophones.isEmpty {
                    Text("No microphones detected. Plug in a microphone or check system permissions.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Input Device", selection: $selectedMicrophone) {
                        Text("System Default").tag("")
                        ForEach(availableMicrophones, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("General") {
                Toggle(isOn: $startAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start at Login")
                        Text("Launch Whisp when you sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: startAtLogin) { _, newValue in
                    updateLoginItem(enabled: newValue)
                }

                Toggle(isOn: $floatingMicrophoneDockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Floating Microphone Dock")
                        Text("Show a floating mic button across all apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $showDockTooltip) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dock Hover Tooltip")
                        Text("Show a tooltip when hovering the floating pill.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!floatingMicrophoneDockEnabled)

                Toggle(isOn: $showDockIcon) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Dock Icon")
                        Text("Display Whisp in the macOS Dock.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: showDockIcon) { _, _ in
                    NotificationCenter.default.post(name: .iconVisibilityPreferencesChanged, object: nil)
                }

                Toggle(isOn: $showMenuBarIcon) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Menu Bar Icon")
                        Text("Display the Whisp icon in the menu bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: showMenuBarIcon) { _, _ in
                    NotificationCenter.default.post(name: .iconVisibilityPreferencesChanged, object: nil)
                }

                Toggle(isOn: $autoBoostMicrophoneVolume) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Boost Microphone")
                        Text("Boost mic volume while recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $enableSmartPaste) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Paste")
                        Text("Paste transcription into the active app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $playCompletionSound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Completion Sound")
                        Text("Play a sound when done.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
            }

            Section("Model Storage") {
                Picker("Storage limit", selection: $maxModelStorageGB) {
                    ForEach(storageOptions, id: \.self) { option in
                        Text("\(Int(option)) GB").tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(VersionInfo.fullVersionInfo)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if VersionInfo.gitHash != "dev-build" && VersionInfo.gitHash != "unknown" {
                    LabeledContent("Git") {
                        Text(VersionInfo.gitHash)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !VersionInfo.buildDate.isEmpty {
                    LabeledContent("Built") {
                        Text(VersionInfo.buildDate)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadMicrophones()
        }
    }

    private func loadMicrophones() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoverySession.devices
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
