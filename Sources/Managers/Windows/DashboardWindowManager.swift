import AppKit
import Foundation
import SwiftUI
import os.log

@MainActor
internal protocol DashboardWindowAppControlling: AnyObject {
    var activationPolicy: NSApplication.ActivationPolicy { get }

    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool

    @discardableResult
    func activate() -> Bool
}

private final class LiveDashboardWindowAppController: DashboardWindowAppControlling {
    var activationPolicy: NSApplication.ActivationPolicy {
        NSApp.activationPolicy()
    }

    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        NSApp.setActivationPolicy(activationPolicy)
    }

    @discardableResult
    func activate() -> Bool {
        NSRunningApplication.current.activate(options: [])
    }
}

/// Manages the dashboard window lifecycle
@MainActor
internal final class DashboardWindowManager: NSObject {
    static let shared = DashboardWindowManager()

    private static let frameAutosaveName = NSWindow.FrameAutosaveName("WhispDashboardWindow")

    private weak var dashboardWindow: NSWindow?
    private var windowDelegate: DashboardWindowDelegate?
    private let selectionModel = DashboardSelectionModel()
    private let isTestEnvironment: Bool
    private let appController: DashboardWindowAppControlling
    private let hasSavedWindowFrame: (NSWindow.FrameAutosaveName) -> Bool
    private let windowFactory: (DashboardSelectionModel) -> NSWindow
    private var restoredActivationPolicy: NSApplication.ActivationPolicy?

    private override init() {
        isTestEnvironment = AppEnvironment.isRunningTests
        appController = LiveDashboardWindowAppController()
        hasSavedWindowFrame = { autosaveName in
            UserDefaults.standard.object(forKey: "NSWindow Frame \(autosaveName)") != nil
        }
        windowFactory = { selectionModel in
            DashboardWindowManager.makeDashboardWindow(selectionModel: selectionModel)
        }
        super.init()
    }

    internal init(
        isTestEnvironment: Bool,
        appController: DashboardWindowAppControlling,
        hasSavedWindowFrame: @escaping (NSWindow.FrameAutosaveName) -> Bool,
        windowFactory: @escaping (DashboardSelectionModel) -> NSWindow
    ) {
        self.isTestEnvironment = isTestEnvironment
        self.appController = appController
        self.hasSavedWindowFrame = hasSavedWindowFrame
        self.windowFactory = windowFactory
        super.init()
    }

    /// Shows the dashboard window, creating it if necessary or bringing existing one to front
    func showDashboardWindow(selectedNav: DashboardNavItem? = nil) {
        if isTestEnvironment {
            return
        }

        if let selectedNav {
            selectionModel.selectedNav = selectedNav
        }

        if let existingWindow = dashboardWindow {
            presentDashboardWindow(existingWindow)
            return
        }

        let window = windowFactory(selectionModel)
        configureDashboardWindow(window)

        windowDelegate = DashboardWindowDelegate(manager: self)
        window.delegate = windowDelegate

        dashboardWindow = window

        presentDashboardWindow(window)

        Logger.app.info("Dashboard window created and shown")
    }

    func windowWillClose() {
        restoreActivationPolicyIfNeeded()
        dashboardWindow = nil
        windowDelegate = nil
        Logger.app.info("Dashboard window closed and references cleaned up")
    }

    private func configureDashboardWindow(_ window: NSWindow) {
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.title = "Whisp Dashboard"
        window.isReleasedWhenClosed = false
        let didRegisterAutosave = window.setFrameAutosaveName(Self.frameAutosaveName)

        if !didRegisterAutosave {
            Logger.app.warning("Dashboard window frame autosave registration failed")
        }

        if !hasSavedWindowFrame(Self.frameAutosaveName) {
            window.center()
        }
    }

    private func presentDashboardWindow(_ window: NSWindow) {
        elevateAppForDashboardIfNeeded()
        window.makeKeyAndOrderFront(nil)

        if !appController.activate() {
            Logger.app.warning("Failed to activate Whisp while showing dashboard window")
        }
    }

    private func elevateAppForDashboardIfNeeded() {
        guard restoredActivationPolicy == nil else { return }

        let currentPolicy = appController.activationPolicy
        guard currentPolicy != .regular else { return }

        guard appController.setActivationPolicy(.regular) else {
            Logger.app.warning("Failed to promote Whisp to regular activation for dashboard window")
            return
        }

        restoredActivationPolicy = currentPolicy
    }

    private func restoreActivationPolicyIfNeeded() {
        guard let policy = restoredActivationPolicy else { return }

        if !appController.setActivationPolicy(policy) {
            Logger.app.warning("Failed to restore Whisp activation policy after closing dashboard window")
            return
        }

        restoredActivationPolicy = nil
    }

    private static func makeDashboardWindow(selectionModel: DashboardSelectionModel) -> NSWindow {
        let dashboardView = DashboardView(selectionModel: selectionModel)
        let hostingController = NSHostingController(rootView: dashboardView)
        let initialSize = LayoutMetrics.DashboardWindow.initialSize
        let minimumSize = LayoutMetrics.DashboardWindow.minimumSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.setContentSize(initialSize)
        window.minSize = minimumSize
        return window
    }
}

private class DashboardWindowDelegate: NSObject, NSWindowDelegate {
    private weak var manager: DashboardWindowManager?

    init(manager: DashboardWindowManager) {
        self.manager = manager
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        manager?.windowWillClose()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
}
