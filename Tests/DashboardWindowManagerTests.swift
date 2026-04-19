import AppKit
import XCTest

@testable import Whisp

@MainActor
final class DashboardWindowManagerTests: XCTestCase {
    func testShowDashboardWindowPromotesAccessoryAppAndRestoresItOnClose() {
        let appController = TestDashboardWindowAppController(activationPolicy: .accessory)
        let window = TestDashboardWindow()
        let manager = DashboardWindowManager(
            isTestEnvironment: false,
            appController: appController,
            hasSavedWindowFrame: { _ in false },
            windowFactory: { _ in window }
        )

        manager.showDashboardWindow()

        XCTAssertEqual(appController.setActivationPolicyCalls, [.regular])
        XCTAssertEqual(appController.activateCalls, 1)
        XCTAssertEqual(window.recordedFrameAutosaveName, "WhispDashboardWindow")
        XCTAssertTrue(window.didMakeKeyAndOrderFront)
        XCTAssertTrue(window.didCenter)

        manager.windowWillClose()

        XCTAssertEqual(appController.setActivationPolicyCalls, [.regular, .accessory])
    }

    func testShowDashboardWindowSkipsCenterAndDoesNotMoveToActiveSpaceWhenFrameExists() {
        let appController = TestDashboardWindowAppController(activationPolicy: .regular)
        let window = TestDashboardWindow()
        let manager = DashboardWindowManager(
            isTestEnvironment: false,
            appController: appController,
            hasSavedWindowFrame: { _ in true },
            windowFactory: { _ in window }
        )

        manager.showDashboardWindow()

        XCTAssertFalse(window.didCenter)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(appController.setActivationPolicyCalls.isEmpty)
        XCTAssertEqual(appController.activateCalls, 1)
    }
}

@MainActor
private final class TestDashboardWindowAppController: DashboardWindowAppControlling {
    var activationPolicy: NSApplication.ActivationPolicy
    var setActivationPolicyCalls: [NSApplication.ActivationPolicy] = []
    var activateCalls = 0

    init(activationPolicy: NSApplication.ActivationPolicy) {
        self.activationPolicy = activationPolicy
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        setActivationPolicyCalls.append(activationPolicy)
        self.activationPolicy = activationPolicy
        return true
    }

    func activate() -> Bool {
        activateCalls += 1
        return true
    }
}

@MainActor
private final class TestDashboardWindow: NSWindow {
    var didCenter = false
    var didMakeKeyAndOrderFront = false
    var recordedFrameAutosaveName: String?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    override func center() {
        didCenter = true
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        didMakeKeyAndOrderFront = true
    }

    override func setFrameAutosaveName(_ name: NSWindow.FrameAutosaveName) -> Bool {
        recordedFrameAutosaveName = name
        return true
    }
}
