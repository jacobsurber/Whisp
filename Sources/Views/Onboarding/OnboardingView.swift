import AVFoundation
import ApplicationServices
import OSLog
import SwiftUI

// MARK: - Onboarding Step

internal enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case engine
    case engineSetup
    case hotkey
    case smartPaste
    case testRecording
    case done

    var progress: Double {
        Double(rawValue) / Double(Self.allCases.count - 1)
    }
}

internal enum OnboardingPressAndHoldKeyChangeDecision: Equatable {
    case persist(PressAndHoldKey)
    case requireConfirmation(previousSelection: PressAndHoldKey, pendingSelection: PressAndHoldKey)
}

internal enum OnboardingPressAndHoldKeySelectionResolver {
    static func resolveChange(
        from oldValue: String,
        to newValue: String,
        warningAcknowledged: Bool
    ) -> OnboardingPressAndHoldKeyChangeDecision {
        let previousSelection = PressAndHoldKey(rawValue: oldValue) ?? PressAndHoldConfiguration.defaults.key
        let pendingSelection = PressAndHoldKey(rawValue: newValue) ?? PressAndHoldConfiguration.defaults.key

        if pendingSelection == .globe && !warningAcknowledged {
            return .requireConfirmation(
                previousSelection: previousSelection,
                pendingSelection: pendingSelection
            )
        }

        return .persist(pendingSelection)
    }
}

internal struct OnboardingPressAndHoldSelectionState: Equatable {
    var persistedKeyIdentifier: String
    var pickerSelection: String
    var previousKeyIdentifier: String
    var pendingKeyIdentifier: String?
    var showFnWarningConfirmation: Bool
}

internal enum OnboardingPressAndHoldSelectionCoordinator {
    static func handlePickerChange(
        state: inout OnboardingPressAndHoldSelectionState,
        from oldValue: String,
        to newValue: String,
        warningAcknowledged: Bool
    ) -> String? {
        switch OnboardingPressAndHoldKeySelectionResolver.resolveChange(
            from: oldValue,
            to: newValue,
            warningAcknowledged: warningAcknowledged
        ) {
        case let .persist(key):
            state.persistedKeyIdentifier = key.rawValue
            state.pickerSelection = key.rawValue
            state.previousKeyIdentifier = key.rawValue
            state.pendingKeyIdentifier = nil
            state.showFnWarningConfirmation = false
            return key.rawValue

        case let .requireConfirmation(previousSelection, pendingSelection):
            state.previousKeyIdentifier = previousSelection.rawValue
            state.pendingKeyIdentifier = pendingSelection.rawValue
            state.pickerSelection = previousSelection.rawValue
            state.showFnWarningConfirmation = true
            return nil
        }
    }

    static func confirmPendingSelection(
        state: inout OnboardingPressAndHoldSelectionState,
        fallbackKeyIdentifier: String = PressAndHoldKey.globe.rawValue
    ) -> String {
        let confirmedIdentifier = state.pendingKeyIdentifier ?? fallbackKeyIdentifier
        state.persistedKeyIdentifier = confirmedIdentifier
        state.pickerSelection = confirmedIdentifier
        state.previousKeyIdentifier = confirmedIdentifier
        state.pendingKeyIdentifier = nil
        state.showFnWarningConfirmation = false
        return confirmedIdentifier
    }

    static func cancelPendingSelection(state: inout OnboardingPressAndHoldSelectionState) {
        state.pendingKeyIdentifier = nil
        state.pickerSelection = state.previousKeyIdentifier
        state.showFnWarningConfirmation = false
    }
}

internal enum OnboardingHotkeyActivationState: Equatable {
    case liveVerification
    case restartRequired
}

internal enum OnboardingHotkeyActivationCoordinator {
    static func resolveState(
        for configuration: PressAndHoldConfiguration,
        requestedInputMonitoringPermissionInSession: Bool,
        isHotkeyReadyForUse: Bool
    ) -> OnboardingHotkeyActivationState {
        guard configuration.enabled, requestedInputMonitoringPermissionInSession, !isHotkeyReadyForUse else {
            return .liveVerification
        }

        return .restartRequired
    }
}

// MARK: - Onboarding View

internal struct OnboardingView: View {
    @Binding var isPresented: Bool

    @State private var step: OnboardingStep = .welcome
    @State private var animateIn = false

    // Microphone
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    // Engine
    @AppStorage(AppDefaults.Keys.transcriptionProvider) private var transcriptionProvider =
        AppDefaults.defaultTranscriptionProvider

    // API keys (cloud engines)
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var apiKeySaved = false

    // Local model
    @State private var isDownloadingModel = false
    @State private var modelReady = false
    @State private var modelManager = ModelManager.shared
    @AppStorage(AppDefaults.Keys.selectedWhisperModel) private var selectedWhisperModel =
        AppDefaults.defaultWhisperModel

    // Hotkey
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
    @AppStorage(AppDefaults.Keys.pressAndHoldFnFailureMessage) private var pressAndHoldFnFailureMessage =
        ""
    @AppStorage(AppDefaults.Keys.pressAndHoldModifierReadiness) private
        var pressAndHoldModifierReadinessRaw =
        PressAndHoldHotkeyReadiness.requiresInputMonitoring.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldModifierFailureMessage) private
        var pressAndHoldModifierFailureMessage = ""
    @State private var hotkeyPickerSelection = PressAndHoldConfiguration.defaults.key.rawValue
    @State private var previousPressAndHoldKeyIdentifier = PressAndHoldConfiguration.defaults.key.rawValue
    @State private var pendingPressAndHoldKeyIdentifier: String?
    @State private var suppressPressAndHoldChangeHandlers = false
    @State private var showFnWarningConfirmation = false
    @State private var requestedHotkeyPermissionInSession = false

    // Smart Paste
    @AppStorage(AppDefaults.Keys.enableSmartPaste) private var enableSmartPaste = true
    @State private var accessibilityGranted = false

    // Test recording
    @State private var testRecorder: AudioRecorder?
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var testResult: String?
    @State private var testError: String?
    @State private var recordingSeconds: Int = 0
    @State private var recordingTimer: Timer?

    // Model download error
    @State private var downloadError: String?

    private let keychainService: KeychainServiceProtocol = KeychainService.shared
    private let inputMonitoringPermissionManager = InputMonitoringPermissionManager()

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            progressBar

            // Step content
            Group {
                switch step {
                case .welcome: welcomeStep
                case .microphone: microphoneStep
                case .engine: engineStep
                case .engineSetup: engineSetupStep
                case .hotkey: hotkeyStep
                case .smartPaste: smartPasteStep
                case .testRecording: testRecordingStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 12)
        }
        .frame(width: 560, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                animateIn = true
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 3)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.7), Color.accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * step.progress, height: 3)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        stepContainer {
            Spacer()

            VStack(spacing: 20) {
                // Animated mic icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 100, height: 100)

                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.pulse, options: .repeating)
                }
                .padding(.bottom, 8)

                Text("Welcome to Whisp")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Voice-to-text, right from your menu bar.\nLet's get you set up in under a minute.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            navigationButtons(
                primary: "Get Started",
                primaryAction: { advance(to: .microphone) }
            )
        }
    }

    // MARK: - Microphone Permission

    private var microphoneStep: some View {
        stepContainer {
            stepHeader(
                icon: "mic.circle.fill",
                iconColor: .blue,
                title: "Microphone Access",
                subtitle: "Whisp needs your microphone to record audio for transcription."
            )

            Spacer()

            VStack(spacing: 16) {
                if micStatus == .authorized {
                    permissionGrantedBadge(text: "Microphone access granted")
                } else {
                    Button("Grant Microphone Access") {
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                            DispatchQueue.main.async {
                                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if micStatus == .denied {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Previously denied. Open System Settings to grant access.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Open System Settings") {
                            openSystemSettings(path: "Privacy_Microphone")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "lock.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Your audio is processed and never stored permanently.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            navigationButtons(
                secondary: "Back",
                secondaryAction: { advance(to: .welcome) },
                primary: "Continue",
                primaryAction: { advance(to: .engine) },
                primaryDisabled: micStatus != .authorized
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    // MARK: - Engine Selection

    private var engineStep: some View {
        stepContainer {
            stepHeader(
                icon: "waveform.circle.fill",
                iconColor: .teal,
                title: "Transcription Engine",
                subtitle: "Choose how Whisp converts your voice to text."
            )

            ScrollView {
                VStack(spacing: 10) {
                    engineCard(
                        provider: .local,
                        icon: "laptopcomputer",
                        name: "WhisperKit",
                        detail: "On-device, private. No internet needed.",
                        badge: "Recommended",
                        badgeColor: .green
                    )
                    engineCard(
                        provider: .openai,
                        icon: "cloud",
                        name: "OpenAI Whisper",
                        detail: "Cloud-powered, high accuracy. Requires API key.",
                        badge: "Cloud",
                        badgeColor: .blue
                    )
                    engineCard(
                        provider: .gemini,
                        icon: "sparkles",
                        name: "Google Gemini",
                        detail: "Cloud transcription via Gemini. Requires API key.",
                        badge: "Cloud",
                        badgeColor: .indigo
                    )
                    engineCard(
                        provider: .parakeet,
                        icon: "bird",
                        name: "Parakeet",
                        detail: "High-accuracy local engine. Requires Python setup.",
                        badge: "Advanced",
                        badgeColor: .orange
                    )
                    engineCard(
                        provider: .gemma,
                        icon: "cpu",
                        name: "Gemma 4",
                        detail: "Transcribe and correct in one pass. Requires setup.",
                        badge: "Advanced",
                        badgeColor: .orange
                    )
                    engineCard(
                        provider: .whisperMLX,
                        icon: "waveform",
                        name: "Whisper MLX",
                        detail: "Fast on-device transcription via MLX.",
                        badge: "Advanced",
                        badgeColor: .orange
                    )
                }
                .padding(.vertical, 4)
            }

            navigationButtons(
                secondary: "Back",
                secondaryAction: { advance(to: .microphone) },
                primary: "Continue",
                primaryAction: { advance(to: .engineSetup) }
            )
        }
    }

    private func engineCard(
        provider: TranscriptionProvider,
        icon: String,
        name: String,
        detail: String,
        badge: String,
        badgeColor: Color
    ) -> some View {
        let isSelected = transcriptionProvider == provider

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                transcriptionProvider = provider
                // Reset engine-specific state when switching
                apiKey = ""
                apiKeySaved = false
                modelReady = false
                isDownloadingModel = false
                loadExistingAPIKey()
                checkModelReady()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))

                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Circle()
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.4) : Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Engine Setup (API Key or Model Download)

    private var engineSetupStep: some View {
        stepContainer {
            switch transcriptionProvider {
            case .openai:
                cloudSetupContent(
                    providerName: "OpenAI",
                    account: "OpenAI",
                    placeholder: "sk-...",
                    hint: "Get your key at platform.openai.com"
                )
            case .gemini:
                cloudSetupContent(
                    providerName: "Gemini",
                    account: "Gemini",
                    placeholder: "AIza...",
                    hint: "Get your key at aistudio.google.com"
                )
            case .local:
                localModelSetupContent
            case .parakeet, .gemma, .whisperMLX:
                advancedEngineSetupContent
            }

            navigationButtons(
                secondary: "Back",
                secondaryAction: { advance(to: .engine) },
                primary: "Continue",
                primaryAction: { advance(to: .hotkey) },
                primaryDisabled: !isEngineSetupComplete
            )
        }
    }

    private func cloudSetupContent(
        providerName: String,
        account: String,
        placeholder: String,
        hint: String
    ) -> some View {
        Group {
            stepHeader(
                icon: "key.fill",
                iconColor: .blue,
                title: "\(providerName) API Key",
                subtitle: hint
            )

            Spacer()

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Group {
                        if showAPIKey {
                            TextField(placeholder, text: $apiKey)
                        } else {
                            SecureField(placeholder, text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: 360)

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(apiKeySaved ? "Saved" : "Save Key") {
                    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    apiKey = trimmedKey
                    keychainService.saveQuietly(trimmedKey, service: "Whisp", account: account)
                    withAnimation { apiKeySaved = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .controlSize(.large)

                if apiKeySaved {
                    permissionGrantedBadge(text: "API key saved securely")
                }
            }

            Spacer()
        }
        .onAppear { loadExistingAPIKey() }
    }

    private var localModelSetupContent: some View {
        Group {
            stepHeader(
                icon: "arrow.down.circle.fill",
                iconColor: .teal,
                title: "Download Model",
                subtitle: "WhisperKit runs entirely on your Mac. Pick a model to download."
            )

            Spacer()

            VStack(spacing: 16) {
                Picker("Model", selection: $selectedWhisperModel) {
                    ForEach(WhisperModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)

                Text(selectedWhisperModel.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if modelReady {
                    permissionGrantedBadge(text: "Model ready")
                } else if isDownloadingModel {
                    VStack(spacing: 8) {
                        ProgressView(value: modelManager.downloadProgress[selectedWhisperModel] ?? 0)
                            .frame(maxWidth: 280)

                        if let progress = modelManager.downloadProgress[selectedWhisperModel] {
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button("Download \(selectedWhisperModel.displayName)") {
                        downloadModel()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if let downloadError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(downloadError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .onAppear { checkModelReady() }
        .onChange(of: selectedWhisperModel) { _, _ in checkModelReady() }
    }

    private var advancedEngineSetupContent: some View {
        Group {
            stepHeader(
                icon: "gearshape.2.fill",
                iconColor: .orange,
                title: "\(transcriptionProvider.displayName) Setup",
                subtitle:
                    "This engine requires additional setup. You can configure it from Settings after onboarding."
            )

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text("Continue to finish onboarding, then open\nSettings > Transcription to complete setup.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
        }
    }

    // MARK: - Hotkey Setup

    private var hotkeyStep: some View {
        stepContainer {
            stepHeader(
                icon: "keyboard.fill",
                iconColor: .purple,
                title: "Recording Hotkey",
                subtitle: "Choose how you want to start recording. If macOS needs a restart, Whisp will finish setup at the end."
            )

            Spacer()

            VStack(spacing: 20) {
                Toggle(isOn: $pressAndHoldEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Press & Hold")
                            .font(.system(size: 14, weight: .medium))
                        Text("Hold a key to record, release to transcribe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .frame(maxWidth: 360)
                .onChange(of: pressAndHoldEnabled) { _, _ in
                    guard !suppressPressAndHoldChangeHandlers else { return }
                    publishPressAndHoldConfiguration()
                }

                if pressAndHoldEnabled {
                    VStack(spacing: 12) {
                        Picker("Key", selection: $hotkeyPickerSelection) {
                            ForEach(PressAndHoldKey.allCases, id: \.rawValue) { key in
                                Text(key.displayName).tag(key.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)
                        .onChange(of: hotkeyPickerSelection) { oldValue, newValue in
                            guard !suppressPressAndHoldChangeHandlers else { return }
                            handlePressAndHoldKeyChange(from: oldValue, to: newValue)
                        }

                        Picker("Behavior", selection: $pressAndHoldModeRaw) {
                            ForEach(PressAndHoldMode.allCases, id: \.rawValue) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)
                        .onChange(of: pressAndHoldModeRaw) { _, _ in
                            guard !suppressPressAndHoldChangeHandlers else { return }
                            publishPressAndHoldConfiguration()
                        }

                        if requiresHotkeyRestart {
                            hotkeyRestartSection
                        } else if isFnGlobeSelected {
                            fnGlobeSetupSection
                        } else {
                            modifierKeySetupSection
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }

                Text("You can also record from the floating dock or menu bar.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            navigationButtons(
                secondary: "Back",
                secondaryAction: { advance(to: .engineSetup) },
                primary: "Continue",
                primaryAction: { advance(to: .smartPaste) }
            )
        }
        .onAppear {
            syncPressAndHoldConfiguration()
            refreshCurrentHotkeySetup(notify: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncPressAndHoldConfiguration()
            refreshCurrentHotkeySetup()
        }
        .alert("Enable Fn / Globe Mode?", isPresented: $showFnWarningConfirmation) {
            Button("Cancel", role: .cancel) {
                var state = hotkeySelectionState
                OnboardingPressAndHoldSelectionCoordinator.cancelPendingSelection(state: &state)
                applyHotkeySelectionState(state)
            }

            Button("Enable Fn / Globe") {
                FnGlobeHotkeyPreferenceStore.setWarningAcknowledged(true)
                requestHotkeyPermissionAccess()
                var state = hotkeySelectionState
                let confirmedIdentifier = OnboardingPressAndHoldSelectionCoordinator.confirmPendingSelection(
                    state: &state
                )
                applyHotkeySelectionState(state)
                applyPressAndHoldKeyIdentifier(confirmedIdentifier)
            }
        } message: {
            Text(
                "Fn / Globe requires extra setup:\n\n1. Grant Input Monitoring permission.\n2. In System Settings > Keyboard, set Press Globe key to Do Nothing.\n3. If it still does not work, quit and reopen Whisp."
            )
        }
    }

    @ViewBuilder
    private var hotkeyRestartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Finish hotkey setup after restart", systemImage: "arrow.clockwise.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text(hotkeyRestartMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Open Settings") {
                    inputMonitoringPermissionManager.openSystemSettings()
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(.top, 4)
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
                        requestHotkeyPermissionAccess()
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
        .frame(maxWidth: 360, alignment: .leading)
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
                        requestHotkeyPermissionAccess()
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
        .frame(maxWidth: 360, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Smart Paste & Accessibility

    private var smartPasteStep: some View {
        stepContainer {
            stepHeader(
                icon: "accessibility.fill",
                iconColor: .green,
                title: "Smart Paste",
                subtitle: "Automatically paste transcriptions into the active app."
            )

            Spacer()

            VStack(spacing: 20) {
                Toggle(isOn: $enableSmartPaste) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Smart Paste")
                            .font(.system(size: 14, weight: .medium))
                        Text("Transcriptions are pasted directly where your cursor is.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .frame(maxWidth: 360)

                if enableSmartPaste {
                    VStack(spacing: 12) {
                        if accessibilityGranted {
                            permissionGrantedBadge(text: "Accessibility access granted")
                        } else {
                            Text("Smart Paste requires Accessibility permission.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button("Open System Settings") {
                                    openSystemSettings(path: "Privacy_Accessibility")
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Refresh") {
                                    accessibilityGranted = AXIsProcessTrusted()
                                }
                                .buttonStyle(.bordered)
                            }

                            Text("Toggle Whisp ON in System Settings > Privacy > Accessibility.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                if !enableSmartPaste {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Transcriptions will be copied to clipboard instead.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            navigationButtons(
                secondary: "Back",
                secondaryAction: { advance(to: .hotkey) },
                primary: "Continue",
                primaryAction: { advance(to: .testRecording) }
            )
        }
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    // MARK: - Test Recording

    private var testRecordingStep: some View {
        stepContainer {
            stepHeader(
                icon: "waveform.badge.mic",
                iconColor: .red,
                title: "Try It Out",
                subtitle: "Record a short clip to make sure everything works."
            )

            Spacer()

            VStack(spacing: 20) {
                if let result = testResult {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)

                        Text("Transcription Result")
                            .font(.system(size: 13, weight: .medium))

                        Text(result)
                            .font(.system(size: 14))
                            .padding(12)
                            .frame(maxWidth: 400, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .textSelection(.enabled)
                    }
                } else if let error = testError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else if isTranscribing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Transcribing...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else if isRecording {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.1))
                                .frame(width: 80, height: 80)

                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 60, height: 60)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.red)
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                        }

                        Text("\(recordingSeconds)s")
                            .font(.system(size: 24, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Button("Stop Recording") {
                            stopTestRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                } else {
                    VStack(spacing: 12) {
                        if requiresHotkeyRestart {
                            Text(
                                "If you granted Input Monitoring, your hotkey may only start working after Whisp restarts. Use the button below to test recording right now."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                        }

                        Button {
                            startTestRecording()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mic.fill")
                                Text("Start Recording")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(testRecorder != nil)

                        Text("Say something short, like \"Hello, this is a test.\"")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            navigationButtons(
                secondary: "Skip",
                secondaryAction: {
                    cleanupRecording()
                    advance(to: .done)
                },
                primary: testResult != nil ? "Finish" : "Skip for Now",
                primaryAction: {
                    cleanupRecording()
                    advance(to: .done)
                }
            )
            .disabled(isRecording || isTranscribing)
        }
    }

    // MARK: - Done

    private var doneStep: some View {
        stepContainer {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(doneAccentColor.opacity(0.08))
                        .frame(width: 100, height: 100)

                    Circle()
                        .fill(doneAccentColor.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: requiresHotkeyRestart ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(doneAccentColor)
                }

                Text(requiresHotkeyRestart ? "One More Step" : "You're All Set")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                VStack(spacing: 8) {
                    Text(donePrimaryMessage)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)

                    Text(doneSecondaryMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow(
                        icon: "waveform.circle.fill", label: "Engine",
                        value: transcriptionProvider.displayName)
                    if pressAndHoldEnabled, let key = PressAndHoldKey(rawValue: pressAndHoldKeyIdentifier) {
                        summaryRow(
                            icon: "keyboard.fill",
                            label: "Hotkey",
                            value: requiresHotkeyRestart
                                ? "Hold \(key.displayName) after restart"
                                : "Hold \(key.displayName)"
                        )
                    }
                    summaryRow(
                        icon: "doc.on.clipboard.fill",
                        label: "Paste",
                        value: enableSmartPaste ? "Smart Paste" : "Clipboard"
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            Spacer()

            if requiresHotkeyRestart, canRestartApplication {
                HStack {
                    Button("Done Later") {
                        completeOnboarding()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Restart to Finish Hotkey Setup") {
                        completeOnboardingAndRestart()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .padding(.bottom, 32)
            } else {
                Button("Done") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Shared Components

    private func stepContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    private func stepHeader(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.bottom, 12)
    }

    private func permissionGrantedBadge(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.08))
        )
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
        }
    }

    private func navigationButtons(
        secondary: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        primary: String,
        primaryAction: @escaping () -> Void,
        primaryDisabled: Bool = false
    ) -> some View {
        HStack {
            if let secondary, let secondaryAction {
                Button(secondary) {
                    secondaryAction()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(primary) {
                primaryAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(primaryDisabled)
        }
        .padding(.top, 8)
    }

    // MARK: - Navigation

    private func advance(to next: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.25)) {
            animateIn = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            step = next
            withAnimation(.easeOut(duration: 0.35)) {
                animateIn = true
            }
        }
    }

    // MARK: - Engine Setup Helpers

    private var isEngineSetupComplete: Bool {
        switch transcriptionProvider {
        case .openai, .gemini:
            return apiKeySaved
        case .local:
            return modelReady
        case .parakeet, .gemma, .whisperMLX:
            return true  // Deferred to Settings
        }
    }

    private var selectedPressAndHoldKey: PressAndHoldKey {
        PressAndHoldKey(rawValue: hotkeyPickerSelection) ?? PressAndHoldConfiguration.defaults.key
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

    private var hotkeySelectionState: OnboardingPressAndHoldSelectionState {
        OnboardingPressAndHoldSelectionState(
            persistedKeyIdentifier: pressAndHoldKeyIdentifier,
            pickerSelection: hotkeyPickerSelection,
            previousKeyIdentifier: previousPressAndHoldKeyIdentifier,
            pendingKeyIdentifier: pendingPressAndHoldKeyIdentifier,
            showFnWarningConfirmation: showFnWarningConfirmation
        )
    }

    private var isFnGlobeSelected: Bool {
        currentPressAndHoldConfiguration.isFnGlobeEnabled
    }

    private var hotkeyActivationState: OnboardingHotkeyActivationState {
        OnboardingHotkeyActivationCoordinator.resolveState(
            for: currentPressAndHoldConfiguration,
            requestedInputMonitoringPermissionInSession: requestedHotkeyPermissionInSession,
            isHotkeyReadyForUse: isHotkeyReadyForUse
        )
    }

    private var requiresHotkeyRestart: Bool {
        hotkeyActivationState == .restartRequired
    }

    private var hotkeyRestartMessage: String {
        if isFnGlobeSelected {
            if fnGlobeReadiness == .requiresInputMonitoring {
                return "Grant Input Monitoring, set Keyboard > Press Globe key to Do Nothing if macOS is using the key, then finish onboarding and reopen Whisp. If you do not want to restart now, you can keep using the dock or menu bar."
            }

            return "Whisp still needs a fresh launch before it can verify Fn / Globe reliably. Finish onboarding and reopen the app, then press Fn / Globe once to confirm recording starts."
        }

        if modifierKeyReadiness == .requiresInputMonitoring {
            return "Grant Input Monitoring, then finish onboarding and reopen Whisp before testing the hotkey. If you do not want to restart now, you can keep using the dock or menu bar."
        }

        return "Whisp still needs a fresh launch before it can verify the hotkey reliably. Finish onboarding and reopen the app, then press the hotkey once to confirm recording starts."
    }

    private var isHotkeyReadyForUse: Bool {
        if isFnGlobeSelected {
            return fnGlobeReadiness == .ready
        }

        return modifierKeyReadiness == .ready
    }

    private var hotkeyStillNeedsPermission: Bool {
        if isFnGlobeSelected {
            return fnGlobeReadiness == .requiresInputMonitoring
        }

        return modifierKeyReadiness == .requiresInputMonitoring
    }

    private var doneAccentColor: Color {
        requiresHotkeyRestart ? Color.accentColor : Color.green
    }

    private var donePrimaryMessage: String {
        requiresHotkeyRestart ? "Whisp saved your hotkey." : "Whisp is ready to go."
    }

    private var doneSecondaryMessage: String {
        guard requiresHotkeyRestart else {
            return "Use the menu bar icon or your hotkey to start recording."
        }

        if hotkeyStillNeedsPermission {
            return "If you granted Input Monitoring, restart Whisp to retry hotkey setup. If not, you can finish now and enable the hotkey later in Settings."
        }

        return "Restart Whisp to finish hotkey setup, then press it once to confirm recording starts. You can keep using the dock or menu bar if you want to restart later."
    }

    private var canRestartApplication: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
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

    private func loadExistingAPIKey() {
        let account = transcriptionProvider == .openai ? "OpenAI" : "Gemini"
        if let existing = keychainService.getQuietly(service: "Whisp", account: account), !existing.isEmpty {
            apiKey = existing
            apiKeySaved = true
        }
    }

    private func checkModelReady() {
        modelReady = WhisperKitStorage.isModelDownloaded(selectedWhisperModel)
    }

    private func publishPressAndHoldConfiguration() {
        let configuration = currentPressAndHoldConfiguration

        PressAndHoldSettings.update(configuration)
        refreshCurrentHotkeySetup(for: configuration, notify: false)
        previousPressAndHoldKeyIdentifier = configuration.key.rawValue
    }

    private func applyHotkeySelectionState(_ state: OnboardingPressAndHoldSelectionState) {
        updatePressAndHoldFormState {
            pressAndHoldKeyIdentifier = state.persistedKeyIdentifier
            hotkeyPickerSelection = state.pickerSelection
            previousPressAndHoldKeyIdentifier = state.previousKeyIdentifier
            pendingPressAndHoldKeyIdentifier = state.pendingKeyIdentifier
            showFnWarningConfirmation = state.showFnWarningConfirmation
        }
    }

    private func updatePressAndHoldFormState(_ updates: () -> Void) {
        suppressPressAndHoldChangeHandlers = true
        updates()
        DispatchQueue.main.async {
            suppressPressAndHoldChangeHandlers = false
        }
    }

    private func syncPressAndHoldConfiguration() {
        let configuration = PressAndHoldSettings.configuration()

        updatePressAndHoldFormState {
            if pressAndHoldEnabled != configuration.enabled {
                pressAndHoldEnabled = configuration.enabled
            }

            if pressAndHoldKeyIdentifier != configuration.key.rawValue {
                pressAndHoldKeyIdentifier = configuration.key.rawValue
            }

            if hotkeyPickerSelection != configuration.key.rawValue {
                hotkeyPickerSelection = configuration.key.rawValue
            }

            previousPressAndHoldKeyIdentifier = configuration.key.rawValue
            pendingPressAndHoldKeyIdentifier = nil

            if pressAndHoldModeRaw != configuration.mode.rawValue {
                pressAndHoldModeRaw = configuration.mode.rawValue
            }
        }
    }

    private func handlePressAndHoldKeyChange(from oldValue: String, to newValue: String) {
        var state = hotkeySelectionState
        let keyIdentifierToPublish = OnboardingPressAndHoldSelectionCoordinator.handlePickerChange(
            state: &state,
            from: oldValue,
            to: newValue,
            warningAcknowledged: pressAndHoldFnWarningAcknowledged
        )
        applyHotkeySelectionState(state)

        if let keyIdentifierToPublish {
            applyPressAndHoldKeyIdentifier(keyIdentifierToPublish)
        }
    }

    private func applyPressAndHoldKeyIdentifier(_ keyIdentifier: String) {
        updatePressAndHoldFormState {
            if hotkeyPickerSelection != keyIdentifier {
                hotkeyPickerSelection = keyIdentifier
            }

            if pressAndHoldKeyIdentifier != keyIdentifier {
                pressAndHoldKeyIdentifier = keyIdentifier
            }

            previousPressAndHoldKeyIdentifier = keyIdentifier
        }
        publishPressAndHoldConfiguration()
    }

    private func refreshCurrentHotkeySetup(
        for configuration: PressAndHoldConfiguration? = nil,
        notify: Bool = true
    ) {
        let configuration = configuration ?? currentPressAndHoldConfiguration
        guard configuration.enabled else { return }

        if configuration.isFnGlobeEnabled {
            refreshFnGlobeSetup(for: configuration, notify: notify)
        } else {
            refreshModifierKeySetup(for: configuration, notify: notify)
        }
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

    private func refreshModifierKeySetup(
        for configuration: PressAndHoldConfiguration? = nil,
        notify: Bool = true
    ) {
        let configuration = configuration ?? currentPressAndHoldConfiguration
        guard configuration.enabled, !configuration.isFnGlobeEnabled else { return }

        PressAndHoldHotkeyPreferenceStore.syncForConfiguration(
            configuration,
            inputMonitoringGranted: inputMonitoringPermissionManager.checkPermission()
        )

        if notify {
            NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
        }
    }

    private func requestHotkeyPermissionAccess() {
        requestedHotkeyPermissionInSession = true
        _ = inputMonitoringPermissionManager.requestPermission()
    }

    private func downloadModel() {
        isDownloadingModel = true
        downloadError = nil

        Task {
            do {
                try await ModelManager.shared.downloadModel(selectedWhisperModel)
                await MainActor.run {
                    isDownloadingModel = false
                    modelReady = true
                }
            } catch {
                await MainActor.run {
                    isDownloadingModel = false
                    downloadError = "Download failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Test Recording

    private func startTestRecording() {
        guard testRecorder == nil, !isRecording, !isTranscribing else { return }

        let recorder = AudioRecorder()
        testRecorder = recorder

        recordingSeconds = 0
        testResult = nil
        testError = nil

        Task { @MainActor in
            let success = await recorder.startRecording()
            if success {
                isRecording = true
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    DispatchQueue.main.async {
                        recordingSeconds += 1
                    }
                }
            } else {
                testRecorder = nil
                testError = "Could not start recording. Check microphone permissions."
            }
        }
    }

    private func stopTestRecording() {
        guard let recorder = testRecorder else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        isTranscribing = true

        Task { @MainActor in
            do {
                guard let audioURL = await recorder.stopRecording() else {
                    isTranscribing = false
                    testRecorder = nil
                    testError = "No audio was captured."
                    return
                }

                let result = try await TranscriptionCoordinator.shared.processRecording(
                    audioURL: audioURL,
                    sessionDuration: TimeInterval(recordingSeconds),
                    shouldPaste: false
                )

                isTranscribing = false
                testRecorder = nil
                testResult = result.isEmpty ? "(No speech detected)" : result
            } catch {
                isTranscribing = false
                testRecorder = nil
                testError = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private func cleanupRecording() {
        if isRecording, let recorder = testRecorder {
            recordingTimer?.invalidate()
            recordingTimer = nil
            isRecording = false
            Task { @MainActor in
                _ = await recorder.stopRecording()
                testRecorder = nil
            }
        }
    }

    // MARK: - Completion

    private func completeOnboarding() {
        markOnboardingComplete()
        isPresented = false
    }

    private func completeOnboardingAndRestart() {
        markOnboardingComplete()

        guard canRestartApplication else {
            isPresented = false
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    Logger.app.error(
                        "Failed to relaunch Whisp after onboarding: \(error.localizedDescription)"
                    )
                    isPresented = false
                    return
                }

                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: AppDefaults.Keys.hasCompletedWelcome)
        UserDefaults.standard.set(
            AppDefaults.currentWelcomeVersion, forKey: AppDefaults.Keys.lastWelcomeVersion)
    }

    // MARK: - System Settings

    private func openSystemSettings(path: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(isPresented: .constant(true))
}
