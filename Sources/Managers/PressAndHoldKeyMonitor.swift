import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os.log

internal enum PressAndHoldMode: String, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold:
            return "Press and Hold"
        case .toggle:
            return "Press to Toggle"
        }
    }
}

internal enum PressAndHoldKey: String, CaseIterable, Identifiable {
    case rightCommand
    case leftCommand
    case rightOption
    case leftOption
    case rightControl
    case leftControl
    case globe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightCommand:
            return "Right Command (⌘)"
        case .leftCommand:
            return "Left Command (⌘)"
        case .rightOption:
            return "Right Option (⌥)"
        case .leftOption:
            return "Left Option (⌥)"
        case .rightControl:
            return "Right Control (⌃)"
        case .leftControl:
            return "Left Control (⌃)"
        case .globe:
            return "Globe / Fn (🌐)"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand:
            return 54
        case .leftCommand:
            return 55
        case .rightOption:
            return 61
        case .leftOption:
            return 58
        case .rightControl:
            return 62
        case .leftControl:
            return 59
        case .globe:
            return 63
        }
    }

    /// Modifier flag that macOS sets when the key is active.
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand, .leftCommand:
            return .command
        case .rightOption, .leftOption:
            return .option
        case .rightControl, .leftControl:
            return .control
        case .globe:
            return .function
        }
    }

    /// The CGEventFlags mask for this key's modifier family.
    var cgEventFlagsMask: CGEventFlags {
        switch self {
        case .rightCommand, .leftCommand:
            return .maskCommand
        case .rightOption, .leftOption:
            return .maskAlternate
        case .rightControl, .leftControl:
            return .maskControl
        case .globe:
            return .maskSecondaryFn
        }
    }
}

internal struct PressAndHoldConfiguration: Equatable {
    var enabled: Bool
    var key: PressAndHoldKey
    var mode: PressAndHoldMode

    var isFnGlobeEnabled: Bool {
        enabled && key == .globe
    }

    var requiresAccessibilityPermission: Bool {
        false
    }

    func requiresInputMonitoringPermission(warningAcknowledged: Bool) -> Bool {
        guard enabled else { return false }
        if isFnGlobeEnabled { return warningAcknowledged }
        return true
    }

    static let defaults = PressAndHoldConfiguration(
        enabled: true,
        key: .rightCommand,
        mode: .hold
    )
}

internal enum PressAndHoldSettings {
    private static let enabledKey = AppDefaults.Keys.pressAndHoldEnabled
    private static let keyIdentifierKey = AppDefaults.Keys.pressAndHoldKeyIdentifier
    private static let modeKey = AppDefaults.Keys.pressAndHoldMode

    static func configuration(using defaults: UserDefaults = .standard) -> PressAndHoldConfiguration {
        let enabled =
            defaults.object(forKey: enabledKey) as? Bool ?? PressAndHoldConfiguration.defaults.enabled
        let keyIdentifier =
            defaults.string(forKey: keyIdentifierKey) ?? PressAndHoldConfiguration.defaults.key.rawValue
        let modeIdentifier =
            defaults.string(forKey: modeKey) ?? PressAndHoldConfiguration.defaults.mode.rawValue

        let key =
            PressAndHoldKey(rawValue: keyIdentifier) ?? legacyKey(from: keyIdentifier)
            ?? PressAndHoldConfiguration.defaults.key
        let mode = PressAndHoldMode(rawValue: modeIdentifier) ?? PressAndHoldConfiguration.defaults.mode

        if key == .globe,
            defaults.object(forKey: AppDefaults.Keys.pressAndHoldFnWarningAcknowledged) == nil
        {
            defaults.set(true, forKey: AppDefaults.Keys.pressAndHoldFnWarningAcknowledged)
        }

        return PressAndHoldConfiguration(enabled: enabled, key: key, mode: mode)
    }

    static func update(_ configuration: PressAndHoldConfiguration, using defaults: UserDefaults = .standard) {
        defaults.set(configuration.enabled, forKey: enabledKey)
        defaults.set(configuration.key.rawValue, forKey: keyIdentifierKey)
        defaults.set(configuration.mode.rawValue, forKey: modeKey)
        defaults.synchronize()

        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
    }

    private static func legacyKey(from rawValue: String) -> PressAndHoldKey? {
        switch rawValue {
        case "option":
            return .leftOption
        case "control":
            return .leftControl
        case "fn", "globe":
            return .globe
        default:
            return nil
        }
    }
}

// MARK: - Modifier Key Readiness

internal enum PressAndHoldHotkeyReadiness: String {
    case requiresInputMonitoring
    case awaitingVerification
    case ready
    case unavailable

    var title: String {
        switch self {
        case .requiresInputMonitoring:
            return "Grant Input Monitoring"
        case .awaitingVerification:
            return "Verify key capture"
        case .ready:
            return "Key ready"
        case .unavailable:
            return "Key unavailable"
        }
    }

    var statusSymbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unavailable:
            return "xmark.octagon.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
}

private enum PressAndHoldHotkeyCopy {
    static let inputMonitoringSetupMessage =
        "Grant Input Monitoring so Whisp can detect the selected modifier key. If Whisp still cannot see the key after granting access, quit and reopen the app."
    static let verificationSetupMessage =
        "Hold the selected modifier key until Whisp starts recording."
    static let readyMessage =
        "Modifier key capture is ready. You can use it as your recording trigger."
    static let startupUnavailableMessage =
        "Whisp could not start modifier key capture on this Mac."
    static let tapDisabledMessage =
        "Modifier key capture stopped responding. Reopen settings and refresh permissions."
    static let recoveredTapMessage =
        "Modifier key capture recovered after a system interruption. Try the key again if the last press was missed."
}

internal enum PressAndHoldHotkeyPreferenceStore {
    static func readiness(using defaults: UserDefaults = .standard) -> PressAndHoldHotkeyReadiness {
        let rawValue =
            defaults.string(forKey: AppDefaults.Keys.pressAndHoldModifierReadiness)
            ?? PressAndHoldHotkeyReadiness.requiresInputMonitoring.rawValue
        return PressAndHoldHotkeyReadiness(rawValue: rawValue) ?? .requiresInputMonitoring
    }

    static func failureMessage(using defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: AppDefaults.Keys.pressAndHoldModifierFailureMessage) ?? ""
    }

    static func setReadiness(
        _ readiness: PressAndHoldHotkeyReadiness,
        message: String? = nil,
        using defaults: UserDefaults = .standard
    ) {
        defaults.set(readiness.rawValue, forKey: AppDefaults.Keys.pressAndHoldModifierReadiness)
        defaults.set(message ?? "", forKey: AppDefaults.Keys.pressAndHoldModifierFailureMessage)
        defaults.synchronize()
    }

    static func syncForConfiguration(
        _ configuration: PressAndHoldConfiguration,
        inputMonitoringGranted: Bool,
        using defaults: UserDefaults = .standard
    ) {
        guard configuration.enabled, !configuration.isFnGlobeEnabled else { return }

        guard inputMonitoringGranted else {
            setReadiness(
                .requiresInputMonitoring,
                message: PressAndHoldHotkeyCopy.inputMonitoringSetupMessage,
                using: defaults
            )
            return
        }

        if readiness(using: defaults) != .ready {
            setReadiness(
                .awaitingVerification,
                message: PressAndHoldHotkeyCopy.verificationSetupMessage,
                using: defaults
            )
        }
    }

    static func message(for readiness: PressAndHoldHotkeyReadiness, failureMessage: String = "") -> String {
        if !failureMessage.isEmpty {
            return failureMessage
        }

        return readiness.title
    }
}

// MARK: - Modifier Key Monitor

/// Observes global keyboard events so that modifier-only keys (e.g. right command)
/// can trigger recording. Uses a CGEventTap at the HID level, which captures events
/// regardless of which app is focused.
internal final class PressAndHoldKeyMonitor {
    internal enum SemanticEvent {
        case modifierKeyChanged(isPressed: Bool)
        case otherKeyPressed
        case tapDisabled
    }

    typealias ReadinessHandler = (PressAndHoldHotkeyReadiness, String) -> Void

    private let configuration: PressAndHoldConfiguration
    private let keyDownHandler: () -> Void
    private let keyUpHandler: (() -> Void)?
    private let readinessHandler: ReadinessHandler
    private let inputMonitoringPermissionManager: InputMonitoringPermissionManager
    private let holdDelay: TimeInterval

    private static let eventMask =
        CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        | CGEventMask(1 << CGEventType.keyDown.rawValue)
        | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
        | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingActivationWorkItem: DispatchWorkItem?
    private var isKeyCurrentlyDown = false
    private var isCaptureActive = false
    private var isKeyPartOfCombination = false
    private var hasVerifiedCapture = false

    // Stuck state recovery: if key remains held for too long, auto-release
    private var stuckStateTimeoutTask: Task<Void, Never>?
    private let stuckStateTimeout: TimeInterval = 120.0

    init(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void,
        keyUpHandler: (() -> Void)? = nil,
        readinessHandler: @escaping ReadinessHandler = { _, _ in },
        inputMonitoringPermissionManager: InputMonitoringPermissionManager =
            InputMonitoringPermissionManager(),
        holdDelay: TimeInterval = 0.12
    ) {
        self.configuration = configuration
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler
        self.readinessHandler = readinessHandler
        self.inputMonitoringPermissionManager = inputMonitoringPermissionManager
        self.holdDelay = holdDelay
    }

    @discardableResult
    func start() -> Bool {
        stop()

        guard configuration.key != .globe else {
            Logger.app.warning(
                "Use FnGlobeMonitor for the Globe / Fn trigger instead of the generic press-and-hold monitor."
            )
            return false
        }

        guard inputMonitoringPermissionManager.checkPermission() else {
            readinessHandler(
                .requiresInputMonitoring,
                PressAndHoldHotkeyCopy.inputMonitoringSetupMessage
            )
            return false
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: Self.eventMask,
                callback: Self.eventTapCallback,
                userInfo: userInfo
            )
        else {
            readinessHandler(
                .unavailable,
                PressAndHoldHotkeyCopy.startupUnavailableMessage
            )
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)

        if !hasVerifiedCapture {
            readinessHandler(
                .awaitingVerification,
                PressAndHoldHotkeyCopy.verificationSetupMessage
            )
        }

        return true
    }

    func stop() {
        resetPendingState()
        endCaptureIfNeeded()
        removeEventTap()
        cancelStuckStateRecovery()
    }

    deinit {
        stop()
    }

    // MARK: - Semantic Event Processing

    func processSemanticEvent(_ event: SemanticEvent) {
        switch event {
        case .modifierKeyChanged(let isPressed):
            if isPressed {
                guard !isKeyCurrentlyDown else { return }
                isKeyCurrentlyDown = true
                isKeyPartOfCombination = false
                scheduleActivation()
            } else {
                guard isKeyCurrentlyDown || isCaptureActive else { return }
                resetPendingState()
                endCaptureIfNeeded()
            }

        case .otherKeyPressed:
            guard isKeyCurrentlyDown, !isCaptureActive else { return }
            isKeyPartOfCombination = true
            cancelPendingActivation()

        case .tapDisabled:
            resetPendingState()
            endCaptureIfNeeded()

            readinessHandler(
                .unavailable,
                PressAndHoldHotkeyCopy.tapDisabledMessage
            )
        }
    }

    func activateKeyIfEligible() {
        guard isKeyCurrentlyDown, !isKeyPartOfCombination, !isCaptureActive else { return }
        isCaptureActive = true

        startStuckStateRecovery()

        if !hasVerifiedCapture {
            hasVerifiedCapture = true
            readinessHandler(.ready, PressAndHoldHotkeyCopy.readyMessage)
        }

        notifyKeyDown()
    }

    // MARK: - Event Handling

    func handleFlagsChanged(keyCode: Int64, flags: CGEventFlags) {
        let monitoredKey = configuration.key

        guard keyCode == Int64(monitoredKey.keyCode) else {
            // Another modifier key changed while ours is pending — treat as combination
            if isKeyCurrentlyDown, !isCaptureActive,
                hasAdditionalModifierFlags(flags, excluding: monitoredKey)
            {
                processSemanticEvent(.otherKeyPressed)
            }
            return
        }

        // Our key changed state. A flagsChanged event with our keyCode means
        // this physical key toggled. Determine direction from tracked state.
        let isPressed = !isKeyCurrentlyDown
        processSemanticEvent(.modifierKeyChanged(isPressed: isPressed))
    }

    func handleKeyDown(keyCode: Int64) {
        guard isKeyCurrentlyDown else { return }
        // Any non-modifier key pressed while our modifier is down = combination
        processSemanticEvent(.otherKeyPressed)
    }

    // MARK: - Private

    private func scheduleActivation() {
        cancelPendingActivation()

        let workItem = DispatchWorkItem { [weak self] in
            self?.activateKeyIfEligible()
        }

        pendingActivationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: workItem)
    }

    private func cancelPendingActivation() {
        pendingActivationWorkItem?.cancel()
        pendingActivationWorkItem = nil
    }

    private func resetPendingState() {
        cancelPendingActivation()
        isKeyCurrentlyDown = false
        isKeyPartOfCombination = false
    }

    private func endCaptureIfNeeded() {
        guard isCaptureActive else { return }

        isCaptureActive = false
        cancelStuckStateRecovery()

        guard let keyUpHandler else { return }
        Task { @MainActor in
            keyUpHandler()
        }
    }

    private func notifyKeyDown() {
        Task { @MainActor [keyDownHandler] in
            keyDownHandler()
        }
    }

    private func removeEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func hasAdditionalModifierFlags(
        _ flags: CGEventFlags, excluding key: PressAndHoldKey
    ) -> Bool {
        var combinationMask: CGEventFlags = [
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskCommand,
        ]

        // Exclude our own key's modifier so we don't flag ourselves
        combinationMask.remove(key.cgEventFlagsMask)

        return !flags.intersection(combinationMask).isEmpty
    }

    private func handleTapDisabled() {
        resetPendingState()
        endCaptureIfNeeded()

        guard let eventTap else {
            readinessHandler(
                .unavailable,
                PressAndHoldHotkeyCopy.tapDisabledMessage
            )
            return
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)

        readinessHandler(
            hasVerifiedCapture ? .ready : .awaitingVerification,
            hasVerifiedCapture
                ? PressAndHoldHotkeyCopy.recoveredTapMessage
                : PressAndHoldHotkeyCopy.verificationSetupMessage
        )
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleTapDisabled()

        case .flagsChanged:
            handleFlagsChanged(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags
            )

        case .keyDown:
            handleKeyDown(keyCode: event.getIntegerValueField(.keyboardEventKeycode))

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func startStuckStateRecovery() {
        stuckStateTimeoutTask?.cancel()

        stuckStateTimeoutTask = Task { [weak self, stuckStateTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(stuckStateTimeout * 1_000_000_000))

            guard let self = self, self.isCaptureActive else { return }

            Logger.app.warning("Press-and-hold key stuck for \(stuckStateTimeout)s - auto-releasing")
            self.processSemanticEvent(.modifierKeyChanged(isPressed: false))
        }
    }

    private func cancelStuckStateRecovery() {
        stuckStateTimeoutTask?.cancel()
        stuckStateTimeoutTask = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<PressAndHoldKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handleEvent(type: type, event: event)
    }
}
