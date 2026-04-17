import AppKit
import XCTest

@testable import Whisp

final class PressAndHoldKeyMonitorTests: XCTestCase {
    private var defaultsSuiteNames: [String] = []

    override func tearDown() {
        defaultsSuiteNames.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        defaultsSuiteNames.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a monitor for direct semantic-event testing (bypasses CGEventTap).
    /// Hold delay is set to zero so `scheduleActivation` fires on the next run-loop tick,
    /// but most tests call `activateKeyIfEligible()` explicitly for determinism.
    private func makeMonitor(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void = {},
        keyUpHandler: (() -> Void)? = nil,
        readinessHandler: @escaping PressAndHoldKeyMonitor.ReadinessHandler = { _, _ in }
    ) -> PressAndHoldKeyMonitor {
        PressAndHoldKeyMonitor(
            configuration: configuration,
            keyDownHandler: keyDownHandler,
            keyUpHandler: keyUpHandler,
            readinessHandler: readinessHandler,
            holdDelay: 0
        )
    }

    private func makeDefaults(file: StaticString = #filePath, line: UInt = #line) -> UserDefaults {
        let suiteName = "PressAndHoldKeyMonitorTests.\(UUID().uuidString)"
        defaultsSuiteNames.append(suiteName)

        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite", file: file, line: line)
            return .standard
        }

        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Drains the main actor queue so Task { @MainActor } dispatches execute.
    private func drainMainQueue() {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1.0)
    }

    // MARK: - PressAndHoldSettings

    func testConfigurationPreservesStoredGlobeSelection() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppDefaults.Keys.pressAndHoldEnabled)
        defaults.set(PressAndHoldKey.globe.rawValue, forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier)
        defaults.set(PressAndHoldMode.hold.rawValue, forKey: AppDefaults.Keys.pressAndHoldMode)

        let configuration = PressAndHoldSettings.configuration(using: defaults)

        XCTAssertEqual(configuration.key, .globe)
    }

    func testConfigurationMapsLegacyFnSelectionToGlobe() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppDefaults.Keys.pressAndHoldEnabled)
        defaults.set("fn", forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier)
        defaults.set(PressAndHoldMode.hold.rawValue, forKey: AppDefaults.Keys.pressAndHoldMode)

        let configuration = PressAndHoldSettings.configuration(using: defaults)

        XCTAssertEqual(configuration.key, .globe)
    }

    func testConfigurationAutoAcknowledgesExistingGlobeSelection() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppDefaults.Keys.pressAndHoldEnabled)
        defaults.set(PressAndHoldKey.globe.rawValue, forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier)

        _ = PressAndHoldSettings.configuration(using: defaults)

        XCTAssertEqual(
            defaults.object(forKey: AppDefaults.Keys.pressAndHoldFnWarningAcknowledged) as? Bool, true)
    }

    func testUpdatePersistsGlobeSelection() {
        let defaults = makeDefaults()
        let configuration = PressAndHoldConfiguration(enabled: true, key: .globe, mode: .toggle)

        PressAndHoldSettings.update(configuration, using: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier),
            PressAndHoldKey.globe.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: AppDefaults.Keys.pressAndHoldMode),
            PressAndHoldMode.toggle.rawValue
        )
    }

    // MARK: - start()

    func testStartReturnsFalseForGlobeKey() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .globe, mode: .hold)
        )

        XCTAssertFalse(monitor.start())
    }

    // MARK: - Semantic Event Processing

    func testKeyDownActivatesAndInvokesHandler() {
        var keyDownCount = 0
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: { keyDownCount += 1 }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()
        drainMainQueue()

        XCTAssertEqual(keyDownCount, 1)
    }

    func testRepeatedKeyDownIgnoredWhilePressed() {
        var keyDownCount = 0
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: { keyDownCount += 1 }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()
        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))  // repeat — ignored
        monitor.activateKeyIfEligible()  // already active — no-op
        drainMainQueue()

        XCTAssertEqual(keyDownCount, 1)
    }

    func testKeyUpInvokesHandlerWhenActive() {
        let expectationUp = expectation(description: "keyUp")
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: { expectationUp.fulfill() }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()
        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: false))

        wait(for: [expectationUp], timeout: 1.0)
    }

    func testKeyUpNotCalledWithoutPriorActivation() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: { XCTFail("Key up should not fire without prior activation") }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: false))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    func testPressReleasePressInvokesHandlerTwice() {
        var keyDownCount = 0
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: { keyDownCount += 1 }
        )

        // First cycle
        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()
        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: false))

        // Second cycle
        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()
        drainMainQueue()

        XCTAssertEqual(keyDownCount, 2)
    }

    // MARK: - Combination Detection

    func testOtherKeyPressedCancelsActivation() {
        var keyDownCount = 0
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: { keyDownCount += 1 }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.processSemanticEvent(.otherKeyPressed)  // combination detected
        monitor.activateKeyIfEligible()  // should not activate
        drainMainQueue()

        XCTAssertEqual(keyDownCount, 0)
    }

    func testOtherKeyPressedIgnoredWhenAlreadyActive() {
        var keyUpCount = 0
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: { keyUpCount += 1 }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()
        monitor.processSemanticEvent(.otherKeyPressed)  // ignored since already active
        drainMainQueue()

        XCTAssertEqual(keyUpCount, 0)
    }

    func testHandleKeyDownTriggersCombination() {
        var keyDownCount = 0
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: { keyDownCount += 1 }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.handleKeyDown(keyCode: 0)  // 'A' key pressed while modifier down
        monitor.activateKeyIfEligible()
        drainMainQueue()

        XCTAssertEqual(keyDownCount, 0)
    }

    // MARK: - Tap Disabled Recovery

    func testTapDisabledEndsCapture() {
        let expectationUp = expectation(description: "keyUp")
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: { expectationUp.fulfill() }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()
        monitor.processSemanticEvent(.tapDisabled)

        wait(for: [expectationUp], timeout: 1.0)
    }

    func testTapDisabledReportsUnavailable() {
        var receivedReadiness: PressAndHoldHotkeyReadiness?
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            readinessHandler: { readiness, _ in receivedReadiness = readiness }
        )

        monitor.processSemanticEvent(.tapDisabled)

        XCTAssertEqual(receivedReadiness, .unavailable)
    }

    // MARK: - Readiness

    func testReadinessHandlerCalledOnFirstActivation() {
        var receivedReadiness: PressAndHoldHotkeyReadiness?
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            readinessHandler: { readiness, _ in receivedReadiness = readiness }
        )

        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()

        XCTAssertEqual(receivedReadiness, .ready)
    }

    func testReadinessOnlyFiredOnceForMultipleActivations() {
        var readyCount = 0
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            readinessHandler: { readiness, _ in
                if readiness == .ready { readyCount += 1 }
            }
        )

        // First cycle
        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()
        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: false))

        // Second cycle
        monitor.processSemanticEvent(.modifierKeyChanged(isPressed: true))
        monitor.activateKeyIfEligible()

        XCTAssertEqual(readyCount, 1)
    }

    // MARK: - PressAndHoldConfiguration

    func testNonGlobeKeyRequiresInputMonitoring() {
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        XCTAssertTrue(config.requiresInputMonitoringPermission(warningAcknowledged: false))
    }

    func testGlobeKeyRequiresWarningAcknowledgement() {
        let config = PressAndHoldConfiguration(enabled: true, key: .globe, mode: .hold)
        XCTAssertFalse(config.requiresInputMonitoringPermission(warningAcknowledged: false))
        XCTAssertTrue(config.requiresInputMonitoringPermission(warningAcknowledged: true))
    }

    func testAccessibilityPermissionNotRequiredForHotkey() {
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        XCTAssertFalse(config.requiresAccessibilityPermission)
    }

    func testDisabledConfigurationRequiresNoPermissions() {
        let config = PressAndHoldConfiguration(enabled: false, key: .rightCommand, mode: .hold)
        XCTAssertFalse(config.requiresInputMonitoringPermission(warningAcknowledged: true))
        XCTAssertFalse(config.requiresAccessibilityPermission)
    }

    // MARK: - PressAndHoldHotkeyPreferenceStore

    func testPreferenceStoreReadWriteCycle() {
        let defaults = makeDefaults()
        PressAndHoldHotkeyPreferenceStore.setReadiness(.ready, message: "OK", using: defaults)

        XCTAssertEqual(PressAndHoldHotkeyPreferenceStore.readiness(using: defaults), .ready)
        XCTAssertEqual(PressAndHoldHotkeyPreferenceStore.failureMessage(using: defaults), "OK")
    }

    func testSyncSetsAwaitingVerificationWhenPermissionGranted() {
        let defaults = makeDefaults()
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)

        PressAndHoldHotkeyPreferenceStore.syncForConfiguration(
            config, inputMonitoringGranted: true, using: defaults
        )

        XCTAssertEqual(
            PressAndHoldHotkeyPreferenceStore.readiness(using: defaults), .awaitingVerification)
    }

    func testSyncSetsRequiresInputMonitoringWhenNotGranted() {
        let defaults = makeDefaults()
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)

        PressAndHoldHotkeyPreferenceStore.syncForConfiguration(
            config, inputMonitoringGranted: false, using: defaults
        )

        XCTAssertEqual(
            PressAndHoldHotkeyPreferenceStore.readiness(using: defaults), .requiresInputMonitoring)
    }

    func testSyncPreservesReadyState() {
        let defaults = makeDefaults()
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        PressAndHoldHotkeyPreferenceStore.setReadiness(.ready, using: defaults)

        PressAndHoldHotkeyPreferenceStore.syncForConfiguration(
            config, inputMonitoringGranted: true, using: defaults
        )

        XCTAssertEqual(PressAndHoldHotkeyPreferenceStore.readiness(using: defaults), .ready)
    }

    func testSyncIgnoresGlobeConfiguration() {
        let defaults = makeDefaults()
        let config = PressAndHoldConfiguration(enabled: true, key: .globe, mode: .hold)

        PressAndHoldHotkeyPreferenceStore.syncForConfiguration(
            config, inputMonitoringGranted: true, using: defaults
        )

        // Should not have set anything — returns default
        XCTAssertEqual(
            PressAndHoldHotkeyPreferenceStore.readiness(using: defaults), .requiresInputMonitoring)
    }
}
