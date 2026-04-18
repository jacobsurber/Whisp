import AVFoundation
import AppKit
import SwiftUI

internal struct DashboardRecordingView: View {
    @AppStorage(AppDefaults.Keys.selectedMicrophone) private var selectedMicrophone = ""
    @AppStorage(AppDefaults.Keys.pressAndHoldEnabled) private var pressAndHoldEnabled =
        PressAndHoldConfiguration.defaults
        .enabled
    @AppStorage(AppDefaults.Keys.pressAndHoldKeyIdentifier) private var pressAndHoldKeyIdentifier =
        PressAndHoldConfiguration
        .defaults.key.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldMode) private var pressAndHoldModeRaw = PressAndHoldConfiguration
        .defaults.mode
        .rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnWarningAcknowledged) private
        var pressAndHoldFnWarningAcknowledged = false
    @AppStorage(AppDefaults.Keys.pressAndHoldFnReadiness) private var pressAndHoldFnReadinessRaw =
        FnGlobeHotkeyReadiness
        .requiresAcknowledgement.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnFailureMessage) private var pressAndHoldFnFailureMessage = ""
    @AppStorage(AppDefaults.Keys.pressAndHoldModifierReadiness) private
        var pressAndHoldModifierReadinessRaw =
        PressAndHoldHotkeyReadiness
        .requiresInputMonitoring.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldModifierFailureMessage) private
        var pressAndHoldModifierFailureMessage = ""

    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var previousPressAndHoldKeyIdentifier = PressAndHoldConfiguration.defaults.key.rawValue
    @State private var showFnWarningConfirmation = false

    private let inputMonitoringPermissionManager = InputMonitoringPermissionManager()

    var body: some View {
        Form {
            Section {
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

                    Text(
                        "Whisp currently records from macOS's active default input device. This menu stores a device reference for troubleshooting only."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Microphone")
            }

            Section {
                Toggle(isOn: $pressAndHoldEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Press & Hold")
                        Text("Hold a modifier key to control recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: pressAndHoldEnabled) { _, _ in
                    publishPressAndHoldConfiguration()
                }

                if pressAndHoldEnabled {
                    Picker("Behavior", selection: $pressAndHoldModeRaw) {
                        ForEach(PressAndHoldMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: pressAndHoldModeRaw) { _, _ in
                        publishPressAndHoldConfiguration()
                    }

                    Picker("Key", selection: $pressAndHoldKeyIdentifier) {
                        ForEach(PressAndHoldKey.allCases, id: \.rawValue) { key in
                            Text(key.displayName).tag(key.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: pressAndHoldKeyIdentifier) { oldValue, newValue in
                        handlePressAndHoldKeyChange(from: oldValue, to: newValue)
                    }

                    if isFnGlobeSelected {
                        fnGlobeSetupSection
                    } else if pressAndHoldEnabled {
                        modifierKeySetupSection
                    }
                }
            } header: {
                Text("Press & Hold")
            } footer: {
                Text(
                    "Hotkeys are optional. You can also start recording from the floating dock. Some keys require extra permissions — see the Access tab."
                )
            }
        }
        .formStyle(.grouped)
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
        .padding(.top, 4)
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
        .padding(.top, 4)
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

    // MARK: - Modifier Key Readiness

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
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoverySession.devices
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
