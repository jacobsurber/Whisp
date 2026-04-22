import AppKit
import os.log

extension AppDelegate {
    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: LocalizedStrings.Menu.quit, action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: ""))
        return menu
    }

    @MainActor @objc func showSettings() {
        Logger.app.info("Settings menu item selected")
        dashboardWindowPresenter.showDashboardWindow(selectedNav: nil)
    }

    @objc func screenConfigurationChanged() {
        AppSetupHelper.resetIconSizeCache()

        if let button = statusItem?.button {
            button.image = AppSetupHelper.createMenuBarIcon()
        }

        FloatingMicrophoneDockManager.shared.refreshPositionIfNeeded()
    }
}
