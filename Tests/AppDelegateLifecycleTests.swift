import AppKit
import XCTest

@testable import Whisp

@MainActor
final class AppDelegateLifecycleTests: XCTestCase {
    func testApplicationShouldHandleReopenShowsDashboardWhenNoWindowIsVisible() {
        let appDelegate = AppDelegate()
        let presenter = TestDashboardWindowPresenter()
        appDelegate.dashboardWindowPresenter = presenter

        let handled = appDelegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(presenter.showDashboardWindowCalls, 1)
        XCTAssertNil(presenter.lastSelectedNav)
    }

    func testApplicationShouldHandleReopenStillShowsDashboardWhenAnotherWindowIsVisible() {
        let appDelegate = AppDelegate()
        let presenter = TestDashboardWindowPresenter()
        appDelegate.dashboardWindowPresenter = presenter

        let handled = appDelegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: true
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(presenter.showDashboardWindowCalls, 1)
    }
}

@MainActor
private final class TestDashboardWindowPresenter: DashboardWindowPresenting {
    private(set) var showDashboardWindowCalls = 0
    private(set) var lastSelectedNav: DashboardNavItem?

    func showDashboardWindow(selectedNav: DashboardNavItem?) {
        showDashboardWindowCalls += 1
        lastSelectedNav = selectedNav
    }
}
