import AVFoundation
import AppKit
import SwiftUI

internal struct DashboardRecordingView: View {
    @AppStorage(AppDefaults.Keys.selectedMicrophone) private var selectedMicrophone = ""
    @AppStorage(AppDefaults.Keys.pressAndHoldEnabled) private var pressAndHoldEnabled =
        PressAndHoldConfiguration.defaults.enabled
    @AppStorage(AppDefaults.Keys.pressAndHoldKeyIdentifier) private var pressAndHoldKeyIdentifier =
        PressAndHoldConfiguration.defaults.key.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldMode) private var pressAndHoldModeRaw =
        PressAndHoldConfiguration.defaults.mode.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnWarningAcknowledged) private
        var pressAndHoldFnWarningAcknowledged = false
    @AppStorage(AppDefaults.Keys.pressAndHoldFnReadiness) private var pressAndHoldFnReadinessRaw =
        FnGlobeHotkeyReadiness.requiresAcknowledgement.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnFailureMessage) private var pressAndHoldFnFailureMessage = ""
    @AppStorage(AppDefaults.Keys.pressAndHoldModifierReadiness) private
        var pressAndHoldModifierReadinessRaw =
        PressAndHoldHotkeyReadiness.requiresInputMonitoring.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldModifierFailureMessage) private
        var pressAndHoldModifierFailureMessage = ""

    @State private var availableMicrophones: [MicrophoneInputDeviceInfo] = []
    @State private var previousPressAndHoldKeyIdentifier = PressAndHoldConfiguration.defaults.key.rawValue
    @State private var showFnWarningConfirmation = false

    private let inputMonitoringPermissionManager = InputMonitoringPermissionManager()
    private let microphoneVolumeManager = MicrophoneVolumeManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                microphoneSection
                pressAndHoldSection

                Text(
                    "Hotkeys are optional. You can also start recording from the floating dock. Some keys require extra permissions — see the Access tab."
                )
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.inkMuted)
                .padding(.horizontal, 2)
            }
            .padding(DashboardTheme.Spacing.lg)
        }
        .background(DashboardTheme.pageBg)
        .onAppear {
            loadMicrophones()
            syncPressAndHoldConfiguration()
        }
        .alert("Enable Fn / Globe Mode?", isPresented: $showFnWarningConfirmation) {
            Button("Cancel", role: .cancel) {
                pressAndHoldKeyIdentifier = previousPressAndHoldKeyIdentifier
            }

            Button("Enable Fn / Globe") {
                FnGlobeHotkeyPreferenceStore.setWarningAcknowledged(true)
                _ = inputMonitoringPermissionManager.requestPermission()
                previousPressAndHoldKeyIdentifier = PressAndHoldKey.globe.rawValue
                publishPressAndHoldConfiguration()
            }
        } message: {
            Text(
                "Fn / Globe requires extra setup:\n\n1. Grant Input Monitoring permission.\n2. In System Settings > Keyboard, set Press Globe key to Do Nothing.\n3. If it still does not work, quit and reopen Whisp."
            )
        }
    }

    private var microphoneSection: some View {
        SettingsSectionCard(title: "Microphone", icon: "mic") {
            if availableMicrophones.isEmpty {
                Text(
                    "No microphones detected. Plug in a microphone or check system permissions."
                )
                .font(.system(size: 13))
                .foregroundStyle(DashboardTheme.inkMuted)
                .padding(.horizontal, DashboardTheme.Spacing.md)
                .padding(.vertical, 12)
            } else {
                SettingsPickerRow(
                    title: "Input Device",
                    selection: $selectedMicrophone,
                    options: [""] + availableMicrophones.map { $0.uid },
                    display: { uid in
                        uid.isEmpty
                            ? "System Default"
                            : availableMicrophones.first(where: { $0.uid == uid })?.name ?? uid
                    }
                )

                SettingsDivider()

                Text(
                    "Leave on System Default to follow macOS. Choose a specific microphone to force Whisp to use that device."
                )
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.inkMuted)
                .padding(.horizontal, DashboardTheme.Spacing.md)
                .padding(.vertical, 8)
            }
        }
    }

    private var pressAndHoldSection: some View {
        SettingsSectionCard(title: "Press & Hold", icon: "keyboard") {
            SettingsToggleRow(
                title: "Enable Press & Hold",
                subtitle: "Hold a modifier key to control recording",
                isOn: $pressAndHoldEnabled
            )
            .onChange(of: pressAndHoldEnabled) { _, _ in
                publishPressAndHoldConfiguration()
            }

            if pressAndHoldEnabled {
                SettingsDivider()

                SettingsPickerRow(
                    title: "Behavior",
                    selection: $pressAndHoldModeRaw,
                    options: PressAndHoldMode.allCases.map { $0.rawValue },
                    display: { rawValue in
                        PressAndHoldMode(rawValue: rawValue)?.displayName ?? rawValue
                    }
                )
                .onChange(of: pressAndHoldModeRaw) { _, _ in
                    publishPressAndHoldConfiguration()
                }

                SettingsDivider()

                SettingsPickerRow(
                    title: "Key",
                    selection: $pressAndHoldKeyIdentifier,
                    options: PressAndHoldKey.allCases.map { $0.rawValue },
                    display: { rawValue in
                        PressAndHoldKey(rawValue: rawValue)?.displayName ?? rawValue
                    }
                )
                .onChange(of: pressAndHoldKeyIdentifier) { oldValue, newValue in
                    handlePressAndHoldKeyChange(from: oldValue, to: newValue)
                }

                if isFnGlobeSelected {
                    SettingsDivider()
                    fnGlobeSetupSection
                        .padding(.horizontal, DashboardTheme.Spacing.md)
                        .padding(.vertical, DashboardTheme.Spacing.sm)
                } else {
                    SettingsDivider()
                    modifierKeySetupSection
                        .padding(.horizontal, DashboardTheme.Spacing.md)
                        .padding(.vertical, DashboardTheme.Spacing.sm)
                }
            }
        }
    }

    @ViewBuilder
    private var fnGlobeSetupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(fnGlobeStatusTitle, systemImage: fnGlobeStatusIcon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(fnGlobeStatusColor)

            Text(fnGlobeStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if fnGlobeReadiness == .requiresAcknowledgement {
                    Button("Enable Fn / Globe Mode") {
                        showFnWarningConfirmation = true
                    }
                }

                if fnGlobeReadiness == .requiresInputMonitoring {
                    Button("Request Access") {
                        _ = inputMonitoringPermissionManager.requestPermission()
                        refreshFnGlobeSetup()
                    }
                }

                if showsFnGlobeSettingsActions {
                    Button("Open Settings") {
                        inputMonitoringPermissionManager.openSystemSettings()
                    }

                    Button("Refresh Status") {
                        refreshFnGlobeSetup()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modifierKeySetupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(modifierKeyStatusTitle, systemImage: modifierKeyStatusIcon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(modifierKeyStatusColor)

            Text(modifierKeyStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if modifierKeyReadiness == .requiresInputMonitoring {
                    Button("Grant Access") {
                        _ = inputMonitoringPermissionManager.requestPermission()
                        refreshModifierKeySetup()
                    }
                }

                if modifierKeyReadiness == .requiresInputMonitoring
                    || modifierKeyReadiness == .awaitingVerification
                    || modifierKeyReadiness == .unavailable
                {
                    Button("Open Settings") {
                        inputMonitoringPermissionManager.openSystemSettings()
                    }

                    Button("Refresh Status") {
                        refreshModifierKeySetup()
                    }
                }
            }
        }
    }

    private var selectedPressAndHoldKey: PressAndHoldKey {
        PressAndHoldKey(rawValue: pressAndHoldKeyIdentifier) ?? PressAndHoldConfiguration.defaults.key
    }

    private var selectedPressAndHoldMode: PressAndHoldMode {
        PressAndHoldMode(rawValue: pressAndHoldModeRaw) ?? PressAndHoldConfiguration.defaults.mode
    }

    private var currentPressAndHoldConfiguration: PressAndHoldConfiguration {
        PressAndHoldConfiguration(
            enabled: pressAndHoldEnabled,
            key: selectedPressAndHoldKey,
            mode: selectedPressAndHoldMode
        )
    }

    private var isFnGlobeSelected: Bool {
        currentPressAndHoldConfiguration.isFnGlobeEnabled
    }

    private var fnGlobeReadiness: FnGlobeHotkeyReadiness {
        FnGlobeHotkeyReadiness(rawValue: pressAndHoldFnReadinessRaw) ?? .requiresAcknowledgement
    }

    private var fnGlobeStatusTitle: String {
        fnGlobeReadiness.title
    }

    private var fnGlobeStatusIcon: String {
        fnGlobeReadiness.statusSymbolName
    }

    private var fnGlobeStatusColor: Color {
        switch fnGlobeReadiness {
        case .ready:
            return Color(nsColor: .systemGreen)
        case .unavailable:
            return Color(nsColor: .systemRed)
        default:
            return Color(nsColor: .systemOrange)
        }
    }

    private var fnGlobeStatusMessage: String {
        FnGlobeHotkeyPreferenceStore.message(
            for: fnGlobeReadiness,
            failureMessage: pressAndHoldFnFailureMessage
        )
    }

    private var showsFnGlobeSettingsActions: Bool {
        switch fnGlobeReadiness {
        case .requiresInputMonitoring, .awaitingVerification, .unavailable:
            return true
        default:
            return false
        }
    }

    private var modifierKeyReadiness: PressAndHoldHotkeyReadiness {
        PressAndHoldHotkeyReadiness(rawValue: pressAndHoldModifierReadinessRaw)
            ?? .requiresInputMonitoring
    }

    private var modifierKeyStatusTitle: String {
        modifierKeyReadiness.title
    }

    private var modifierKeyStatusIcon: String {
        modifierKeyReadiness.statusSymbolName
    }

    private var modifierKeyStatusColor: Color {
        switch modifierKeyReadiness {
        case .ready:
            return Color(nsColor: .systemGreen)
        case .unavailable:
            return Color(nsColor: .systemRed)
        default:
            return Color(nsColor: .systemOrange)
        }
    }

    private var modifierKeyStatusMessage: String {
        PressAndHoldHotkeyPreferenceStore.message(
            for: modifierKeyReadiness,
            failureMessage: pressAndHoldModifierFailureMessage
        )
    }

    private func loadMicrophones() {
        availableMicrophones = microphoneVolumeManager.availableInputDevices()
    }

    private func publishPressAndHoldConfiguration() {
        let configuration = currentPressAndHoldConfiguration

        PressAndHoldSettings.update(configuration)
        refreshFnGlobeSetup(for: configuration, notify: false)
        syncPressAndHoldConfiguration(configuration)
    }

    private func handlePressAndHoldKeyChange(from oldValue: String, to newValue: String) {
        if newValue == PressAndHoldKey.globe.rawValue && !pressAndHoldFnWarningAcknowledged {
            previousPressAndHoldKeyIdentifier = oldValue
            showFnWarningConfirmation = true
            return
        }

        previousPressAndHoldKeyIdentifier = newValue
        publishPressAndHoldConfiguration()
    }

    private func refreshFnGlobeSetup(
        for configuration: PressAndHoldConfiguration? = nil,
        notify: Bool = true
    ) {
        let configuration = configuration ?? currentPressAndHoldConfiguration

        guard configuration.isFnGlobeEnabled else { return }

        FnGlobeHotkeyPreferenceStore.syncForConfiguration(
            configuration,
            inputMonitoringGranted: inputMonitoringPermissionManager.checkPermission()
        )

        if notify {
            NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
        }
    }

    private func refreshModifierKeySetup(notify: Bool = true) {
        let configuration = currentPressAndHoldConfiguration

        guard configuration.enabled, !configuration.isFnGlobeEnabled else { return }

        PressAndHoldHotkeyPreferenceStore.syncForConfiguration(
            configuration,
            inputMonitoringGranted: inputMonitoringPermissionManager.checkPermission()
        )

        if notify {
            NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
        }
    }

    private func syncPressAndHoldConfiguration() {
        syncPressAndHoldConfiguration(PressAndHoldSettings.configuration())
    }

    private func syncPressAndHoldConfiguration(_ configuration: PressAndHoldConfiguration) {
        if pressAndHoldEnabled != configuration.enabled {
            pressAndHoldEnabled = configuration.enabled
        }

        if pressAndHoldKeyIdentifier != configuration.key.rawValue {
            pressAndHoldKeyIdentifier = configuration.key.rawValue
        }

        previousPressAndHoldKeyIdentifier = configuration.key.rawValue

        if pressAndHoldModeRaw != configuration.mode.rawValue {
            pressAndHoldModeRaw = configuration.mode.rawValue
        }
    }
}

#Preview {
    DashboardRecordingView()
        .frame(width: 900, height: 700)
}
