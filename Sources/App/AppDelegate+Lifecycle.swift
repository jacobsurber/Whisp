import AppKit
import os.log

extension AppDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip UI initialization in test environment
        let isTestEnvironment = NSClassFromString("XCTestCase") != nil
        if isTestEnvironment {
            Logger.app.info("Test environment detected - skipping UI initialization")
            return
        }

        // Ensure a single, consistent set of defaults before any UI/services read from UserDefaults/AppStorage.
        AppDefaults.register()

        // Migrate model assets from legacy scattered locations into the unified
        // ~/Documents/Models/ tree. Idempotent — skips if the migration sentinel
        // already exists.
        ModelStorageMigration.migrateIfNeeded()

        do {
            try DataManager.shared.initialize()
            Logger.app.info("DataManager initialized successfully")
        } catch {
            Logger.app.error("Failed to initialize DataManager: \(error.localizedDescription)")
            // App continues with in-memory fallback
        }

        Task { await UsageMetricsStore.shared.bootstrapIfNeeded() }

        AppSetupHelper.setupApp()

        audioRecorder = AudioRecorder()

        // Pre-load services to eliminate first-use slowness
        Task {
            await preloadServices()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = AppSetupHelper.createMenuBarIcon()
        }
        statusItem?.menu = makeStatusMenu()

        if let audioRecorder {
            FloatingMicrophoneDockManager.shared.configure(
                recorder: audioRecorder,
                primaryAction: { [weak self] in
                    self?.handleFloatingMicrophoneDockPrimaryAction()
                },
                cancelAction: { [weak self] in
                    self?.cancelFloatingMicrophoneDockRecording()
                },
                openSettingsAction: { [weak self] in
                    self?.showFloatingMicrophoneDockSettings()
                }
            )
        }

        configureShortcutMonitors()

        // Auto-open dashboard on first launch or welcome version bump so onboarding sheet is presented
        let hasCompletedWelcome = UserDefaults.standard.bool(forKey: AppDefaults.Keys.hasCompletedWelcome)
        let lastWelcomeVersion =
            UserDefaults.standard.string(forKey: AppDefaults.Keys.lastWelcomeVersion) ?? "0"
        if !hasCompletedWelcome || lastWelcomeVersion != AppDefaults.currentWelcomeVersion {
            DashboardWindowManager.shared.showDashboardWindow()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        setupNotificationObservers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // Keep app running in menu bar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        dashboardWindowPresenter.showDashboardWindow(selectedNav: nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await MLDaemonManager.shared.shutdown() }
        recordingAnimationTimer?.cancel()
        recordingAnimationTimer = nil
        FloatingMicrophoneDockManager.shared.stop()
    }

    func hasAPIKey(service: String, account: String) -> Bool {
        KeychainService.shared.getQuietly(service: service, account: account) != nil
    }

    /// Pre-load services to eliminate first-use slowness
    private func preloadServices() async {
        let provider =
            UserDefaults.standard.string(forKey: AppDefaults.Keys.transcriptionProvider)
            .flatMap { TranscriptionProvider(rawValue: $0) } ?? AppDefaults.defaultTranscriptionProvider

        // Pre-load WhisperKit model if using local provider
        if provider == .local {
            let selectedModel =
                UserDefaults.standard.string(forKey: AppDefaults.Keys.selectedWhisperModel)
                .flatMap { WhisperModel(rawValue: $0) } ?? AppDefaults.defaultWhisperModel

            if WhisperKitStorage.isModelDownloaded(selectedModel) {
                do {
                    Logger.app.info("Pre-loading WhisperKit model: \(selectedModel.displayName)...")
                    try await LocalWhisperService.shared.preloadModel(selectedModel) { progress in
                        Logger.app.debug("Pre-loading: \(progress)")
                    }
                    Logger.app.info("WhisperKit model pre-loaded successfully")
                } catch {
                    Logger.app.error("Failed to pre-load WhisperKit model: \(error.localizedDescription)")
                }
            }
        }

        // Warm up ML daemon if semantic correction is enabled
        let semanticMode =
            UserDefaults.standard.string(forKey: AppDefaults.Keys.semanticCorrectionMode)
            .flatMap { SemanticCorrectionMode(rawValue: $0) } ?? .off

        if semanticMode != .off {
            Logger.app.info("Warming up ML daemon...")
            _ = await MLDaemonManager.shared.ping()
            Logger.app.info("ML daemon ready")
        }
    }
}
