import AppKit
import SwiftUI

// MARK: - Dashboard Theme
internal enum DashboardTheme {
    // Sidebar - standard system colors
    static let sidebarDark = Color(nsColor: .windowBackgroundColor)
    static let sidebarLight = Color(nsColor: .controlBackgroundColor)
    static let sidebarText = Color(nsColor: .labelColor)
    static let sidebarTextMuted = Color(nsColor: .secondaryLabelColor)
    static let sidebarTextFaint = Color(nsColor: .tertiaryLabelColor)
    static let sidebarDivider = Color(nsColor: .separatorColor)
    static let sidebarAccent = Color.accentColor
    static let sidebarAccentSubtle = Color.accentColor.opacity(0.1)

    // Main content - Standard macOS appearance
    static let pageBg = Color(nsColor: .windowBackgroundColor)
    static let cardBg = Color(nsColor: .controlBackgroundColor)
    static let cardBgAlt = Color(nsColor: .controlBackgroundColor)

    // Text - Standard macOS
    static let ink = Color(nsColor: .labelColor)
    static let inkLight = Color(nsColor: .secondaryLabelColor)
    static let inkMuted = Color(nsColor: .tertiaryLabelColor)
    static let inkFaint = Color(nsColor: .quaternaryLabelColor)

    // Accent - System accent
    static let accent = Color.accentColor
    static let accentLight = Color.accentColor.opacity(0.12)
    static let accentSubtle = Color.accentColor.opacity(0.06)

    // Borders & Dividers - Standard macOS
    static let rule = Color(nsColor: .separatorColor)
    static let ruleBold = Color(nsColor: .gridColor)

    // Provider colors (system-leaning)
    static let providerOpenAI = Color(nsColor: .systemBlue)
    static let providerGemini = Color(nsColor: .systemIndigo)
    static let providerLocal = Color(nsColor: .systemTeal)
    static let providerParakeet = Color(nsColor: .systemGreen)

    // Activity heatmap (system grays)
    static let heatmapEmpty = Color(nsColor: .separatorColor)
    static let heatmapLow = Color(nsColor: .quaternaryLabelColor)
    static let heatmapMedium = Color(nsColor: .tertiaryLabelColor)
    static let heatmapHigh = Color(nsColor: .secondaryLabelColor)
    static let heatmapMax = Color(nsColor: .labelColor).opacity(0.6)

    // Semantic colors - adaptive to light/dark mode
    static let success = Color(nsColor: .systemGreen)
    static let destructive = Color(nsColor: .systemRed)

    // Typography - standard macOS system fonts
    enum Fonts {
        static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // Spacing system (8pt base)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
}

// MARK: - Navigation Item
internal enum DashboardNavItem: String, CaseIterable, Identifiable, Hashable {
    case providers = "Transcription"
    case recording = "Recording"
    case history = "History"
    case preferences = "Preferences"
    case permissions = "Access"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .providers: return "waveform.circle"
        case .recording: return "keyboard"
        case .history: return "clock.arrow.circlepath"
        case .preferences: return "gearshape"
        case .permissions: return "lock.shield"
        }
    }

    var description: String {
        switch self {
        case .providers: return "Choose your engine and model"
        case .recording: return "Microphone and shortcuts"
        case .history: return "Past transcriptions"
        case .preferences: return "Startup, paste, and sound"
        case .permissions: return "Microphone and system access"
        }
    }
}

// MARK: - Main Dashboard View
internal struct DashboardView: View {
    @ObservedObject var selectionModel: DashboardSelectionModel
    @AppStorage(AppDefaults.Keys.hasCompletedWelcome) private var hasCompletedWelcome = false
    @AppStorage(AppDefaults.Keys.lastWelcomeVersion) private var lastWelcomeVersion = "0"
    @State private var showOnboarding = false

    init(selectionModel: DashboardSelectionModel = DashboardSelectionModel()) {
        self.selectionModel = selectionModel
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Whisp")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Settings")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                // Navigation items
                List(DashboardNavItem.allCases, selection: $selectionModel.selectedNav) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text(item.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 24)
                    }
                    .padding(.vertical, 4)
                    .tag(item)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .toolbar(removing: .sidebarToggle)
            .frame(minWidth: 220)
        } detail: {
            if let selectedNav = selectionModel.selectedNav {
                detailView(for: selectedNav)
                    .navigationTitle(selectedNav.rawValue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a section")
                        .font(.headline)
                    Text("Choose a settings category from the sidebar")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .interactiveDismissDisabled()
        }
        .onAppear {
            if !hasCompletedWelcome || lastWelcomeVersion != AppDefaults.currentWelcomeVersion {
                showOnboarding = true
            }
        }
    }

    @ViewBuilder
    private func detailView(for item: DashboardNavItem) -> some View {
        switch item {
        case .providers:
            DashboardProvidersView()
        case .recording:
            DashboardRecordingView()
        case .history:
            DashboardHistoryView()
        case .preferences:
            DashboardPreferencesView()
        case .permissions:
            DashboardPermissionsView()
        }
    }
}

// MARK: - Preview
#Preview("Dashboard") {
    DashboardView()
        .frame(
            width: LayoutMetrics.DashboardWindow.previewSize.width,
            height: LayoutMetrics.DashboardWindow.previewSize.height)
}
