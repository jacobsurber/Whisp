import SwiftUI

internal enum FloatingMicrophoneDockVisualStyle: Equatable {
    case collapsedIdle
    case expandedIdle
    case shortcutListening
    case recordingControls
}

internal enum FloatingMicrophoneDockLayout {
    static func size(for style: FloatingMicrophoneDockVisualStyle) -> CGSize {
        switch style {
        case .collapsedIdle:
            return LayoutMetrics.FloatingDock.collapsedSize
        case .expandedIdle:
            return LayoutMetrics.FloatingDock.expandedSize
        case .shortcutListening:
            return LayoutMetrics.FloatingDock.shortcutCaptureSize
        case .recordingControls:
            return LayoutMetrics.FloatingDock.recordingControlsSize
        }
    }
}

@MainActor
internal final class FloatingMicrophoneDockViewModel: ObservableObject {
    private enum RecordingPresentation: Equatable {
        case shortcutHold
        case interactive
    }

    @Published private(set) var status: AppStatus = .ready
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var visualStyle: FloatingMicrophoneDockVisualStyle = .collapsedIdle

    private var isRecording = false
    private var isProcessing = false
    private var hasPermission = true
    private var isHovering = false
    private var pendingRecordingPresentation: RecordingPresentation?
    private var activeRecordingPresentation: RecordingPresentation?
    private var successResetTask: Task<Void, Never>?
    private let successResetDelay: Duration

    init(successResetDelay: Duration = .seconds(1.2)) {
        self.successResetDelay = successResetDelay
    }

    deinit {
        successResetTask?.cancel()
    }

    var isPrimaryActionEnabled: Bool {
        if case .processing = status {
            return false
        }

        return true
    }

    func applyRecorderState(isRecording: Bool, audioLevel: Float, hasPermission: Bool) {
        let wasRecording = self.isRecording

        self.isRecording = isRecording
        self.audioLevel = audioLevel
        self.hasPermission = hasPermission

        if isRecording {
            if let pendingRecordingPresentation {
                activeRecordingPresentation = pendingRecordingPresentation
                self.pendingRecordingPresentation = nil
            } else if activeRecordingPresentation == nil {
                activeRecordingPresentation = .interactive
            }

            isProcessing = false
            cancelSuccessReset()
        } else if wasRecording {
            activeRecordingPresentation = nil
            pendingRecordingPresentation = nil
        }

        refreshStatus()
        refreshVisualStyle()
    }

    func handleTranscriptionStarted() {
        isProcessing = true
        pendingRecordingPresentation = nil
        activeRecordingPresentation = nil
        cancelSuccessReset()
        refreshStatus()
        refreshVisualStyle()
    }

    func handleTranscriptionCompleted() {
        isProcessing = false

        guard hasPermission else {
            refreshStatus()
            refreshVisualStyle()
            return
        }

        status = .success
        refreshVisualStyle()
        scheduleSuccessReset()
    }

    func setHovering(_ isHovering: Bool) {
        self.isHovering = isHovering
        refreshVisualStyle()
    }

    func prepareForShortcutActivation(mode: PressAndHoldMode) {
        pendingRecordingPresentation = (mode == .hold) ? .shortcutHold : .interactive
        refreshVisualStyle()
    }

    func prepareForDockActivation() {
        pendingRecordingPresentation = .interactive
        refreshVisualStyle()
    }

    func handleRecordingStartFailed() {
        pendingRecordingPresentation = nil
        activeRecordingPresentation = nil
        refreshVisualStyle()
    }

    func resetInteractionState() {
        pendingRecordingPresentation = nil
        activeRecordingPresentation = nil
        refreshVisualStyle()
    }

    private func refreshStatus() {
        if isRecording {
            status = .recording
        } else if isProcessing {
            status = .processing("Transcribing...")
        } else if !hasPermission {
            status = .permissionRequired
        } else if case .success = status {
            return
        } else {
            status = .ready
        }
    }

    private func scheduleSuccessReset() {
        cancelSuccessReset()

        successResetTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: self.successResetDelay)
            guard !Task.isCancelled else { return }

            if self.isRecording {
                self.status = .recording
            } else if self.isProcessing {
                self.status = .processing("Transcribing...")
            } else if self.hasPermission {
                self.status = .ready
            } else {
                self.status = .permissionRequired
            }

            self.refreshVisualStyle()
        }
    }

    private func cancelSuccessReset() {
        successResetTask?.cancel()
        successResetTask = nil
    }

    private func refreshVisualStyle() {
        if let pendingRecordingPresentation {
            visualStyle =
                pendingRecordingPresentation == .shortcutHold
                ? .shortcutListening : .recordingControls
            return
        }

        if isRecording {
            visualStyle =
                activeRecordingPresentation == .shortcutHold
                ? .shortcutListening : .recordingControls
            return
        }

        if status != .ready {
            visualStyle = .expandedIdle
            return
        }

        visualStyle = isHovering ? .expandedIdle : .collapsedIdle
    }
}

internal struct FloatingMicrophoneDockView: View {
    @ObservedObject var viewModel: FloatingMicrophoneDockViewModel
    @AppStorage(AppDefaults.Keys.pressAndHoldEnabled) private var pressAndHoldEnabled =
        PressAndHoldConfiguration.defaults.enabled
    @AppStorage(AppDefaults.Keys.pressAndHoldKeyIdentifier) private var pressAndHoldKeyIdentifier =
        PressAndHoldConfiguration.defaults.key.rawValue
    @State private var isPrimaryButtonHovered = false

    let onPrimaryAction: () -> Void
    let onCancelAction: () -> Void
    let onSettingsAction: () -> Void

    private let shell = Color.black.opacity(0.84)
    private let quietShell = Color.black.opacity(0.22)
    private let shellBorder = Color.white.opacity(0.16)
    private let shellHighlight = Color.white.opacity(0.05)
    private let text = Color.white.opacity(0.96)
    private let mutedText = Color.white.opacity(0.62)
    private let handleStroke = Color.white.opacity(0.72)
    private let handleFill = Color.white.opacity(0.06)
    private let subtleFill = Color.white.opacity(0.08)
    private let brandWarm = Color(red: 0.90, green: 0.68, blue: 0.24)
    private let danger = Color(red: 0.88, green: 0.35, blue: 0.28)

    var body: some View {
        ZStack {
            switch viewModel.visualStyle {
            case .collapsedIdle:
                collapsedDock
            case .expandedIdle:
                expandedDock
            case .shortcutListening:
                shortcutCaptureDock
            case .recordingControls:
                recordingDock
            }
        }
        .frame(
            width: FloatingMicrophoneDockLayout.size(for: viewModel.visualStyle).width,
            height: FloatingMicrophoneDockLayout.size(for: viewModel.visualStyle).height
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            viewModel.setHovering(isHovering)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: viewModel.visualStyle)
        .animation(.easeInOut(duration: 0.18), value: viewModel.status)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var collapsedDock: some View {
        Button(action: onPrimaryAction) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(handleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(handleStroke, lineWidth: 0.8)
                )
                .frame(width: 34, height: 7)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .help("Click to start dictating")
    }

    private var expandedDock: some View {
        VStack(spacing: 8) {
            Button(action: onSettingsAction) {
                Text(primaryText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(text)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .frame(minWidth: 300)
                    .frame(height: 44)
                    .background(capsuleBackground)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                isPrimaryButtonHovered = isHovering
            }

            dotsPill
        }
        .overlay(alignment: .top) {
            if isPrimaryButtonHovered {
                primaryTooltip
                    .offset(y: -46)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var shortcutCaptureDock: some View {
        DockWaveformView(
            audioLevel: viewModel.audioLevel,
            barCount: 7,
            tint: brandWarm,
            barWidth: 2,
            spacing: 2,
            frameHeight: 12,
            minimumBarHeight: 3,
            animationLift: 2.4,
            voiceLiftScale: 5.2
        )
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(quietCapsuleBackground)
    }

    private var recordingDock: some View {
        HStack(spacing: 10) {
            Button(action: onCancelAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(text)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(subtleFill)
                    )
            }
            .buttonStyle(.plain)
            .help("Cancel dictation")

            DockWaveformView(audioLevel: viewModel.audioLevel, barCount: 10, tint: brandWarm)

            Button(action: onPrimaryAction) {
                ZStack {
                    Circle()
                        .fill(danger)
                        .frame(width: 22, height: 22)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Stop and transcribe")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(capsuleBackground)
    }

    private var capsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(shell)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(shellBorder, lineWidth: 1)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(shellHighlight, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
    }

    private var smallCapsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(shell)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(shellBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
    }

    private var quietCapsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(quietShell)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(handleStroke.opacity(0.42), lineWidth: 0.8)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private var dotsPill: some View {
        Button(action: onPrimaryAction) {
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    Circle()
                        .fill(mutedText)
                        .frame(width: 2.25, height: 2.25)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(smallCapsuleBackground)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isPrimaryActionEnabled)
        .help("Click to start dictating")
    }

    private var selectedPressAndHoldKey: PressAndHoldKey {
        PressAndHoldKey(rawValue: pressAndHoldKeyIdentifier) ?? PressAndHoldConfiguration.defaults.key
    }

    private var isRecording: Bool {
        if case .recording = viewModel.status {
            return true
        }

        return false
    }

    private var primaryText: String {
        switch viewModel.status {
        case .recording:
            return "Listening"
        case .processing:
            return "Transcribing…"
        case .success:
            return "Transcript ready"
        case .permissionRequired:
            return "Click to allow microphone"
        case .error(let message):
            return message
        case .downloadingModel(let message):
            return message
        case .ready:
            return readyPromptText
        }
    }

    private var readyPromptText: String {
        guard pressAndHoldEnabled else {
            return "Click to start dictating"
        }

        if selectedPressAndHoldKey == .globe {
            return "Click or hold fn to start dictating"
        }

        return "Click or use hotkey to start dictating"
    }

    private var primaryButtonHelp: String {
        switch viewModel.status {
        case .permissionRequired:
            return "Request microphone access"
        case .processing:
            return "Whisp is transcribing"
        case .success:
            return "Ready for the next dictation"
        default:
            return "Start dictation"
        }
    }

    private var primaryTooltip: some View {
        Text(primaryButtonHelp)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.94))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        switch viewModel.status {
        case .recording:
            return "Whisp dock, currently recording"
        case .processing:
            return "Whisp dock, processing transcript"
        case .success:
            return "Whisp dock, transcription completed"
        case .permissionRequired:
            return "Whisp dock, microphone permission required"
        case .error(let message):
            return "Whisp dock, error: \(message)"
        case .downloadingModel(let message):
            return "Whisp dock, model download in progress: \(message)"
        case .ready:
            return "Whisp dock, ready to record"
        }
    }

    private var accessibilityHint: String {
        switch viewModel.status {
        case .recording:
            return "Use the left button to cancel or the right button to stop and transcribe."
        case .processing:
            return "Whisp is currently processing audio."
        default:
            return
                "Hover to expand the dock. Click the main pill to start dictation, or use the smaller pill for settings."
        }
    }
}

private struct DockWaveformView: View {
    let audioLevel: Float
    let barCount: Int
    let tint: Color
    let barWidth: CGFloat
    let spacing: CGFloat
    let frameHeight: CGFloat
    let minimumBarHeight: CGFloat
    let animationLift: CGFloat
    let voiceLiftScale: CGFloat

    init(
        audioLevel: Float,
        barCount: Int,
        tint: Color,
        barWidth: CGFloat = 3,
        spacing: CGFloat = 3,
        frameHeight: CGFloat = 24,
        minimumBarHeight: CGFloat = 5,
        animationLift: CGFloat = 5,
        voiceLiftScale: CGFloat = 10
    ) {
        self.audioLevel = audioLevel
        self.barCount = barCount
        self.tint = tint
        self.barWidth = barWidth
        self.spacing = spacing
        self.frameHeight = frameHeight
        self.minimumBarHeight = minimumBarHeight
        self.animationLift = animationLift
        self.voiceLiftScale = voiceLiftScale
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: barWidth, height: barHeight(for: index, time: time))
                }
            }
            .frame(
                width: CGFloat(barCount) * barWidth + CGFloat(max(barCount - 1, 0)) * spacing,
                height: frameHeight
            )
        }
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        let normalizedLevel = max(0.08, min(CGFloat(audioLevel), 1))
        let pattern: [CGFloat] = [0.24, 0.42, 0.68, 0.92, 0.78, 0.54, 0.36, 0.62, 0.86, 0.58]
        let phase = CGFloat((sin((time * 7) + (Double(index) * 0.8)) + 1) / 2)
        let animatedLift = 0.8 + (phase * animationLift)
        let voiceLift = normalizedLevel * pattern[index % pattern.count] * voiceLiftScale
        return minimumBarHeight + animatedLift + voiceLift
    }
}

#Preview("Floating Dock") {
    let viewModel = FloatingMicrophoneDockViewModel()
    viewModel.applyRecorderState(isRecording: false, audioLevel: 0, hasPermission: true)

    return FloatingMicrophoneDockView(
        viewModel: viewModel,
        onPrimaryAction: {},
        onCancelAction: {},
        onSettingsAction: {}
    )
    .padding(24)
    .background(Color.black)
}
