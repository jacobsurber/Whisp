import AppKit
import SwiftUI

// MARK: - Dashboard Theme
internal enum DashboardTheme {
    // Brand amber — matches the floating dock's warm accent
    static let brand = Color(red: 0.91, green: 0.68, blue: 0.21)
    static let brandMuted = brand.opacity(0.15)
    static let brandSubtle = brand.opacity(0.08)

    // Sidebar
    static let sidebarDark = Color(nsColor: .windowBackgroundColor)
    static let sidebarLight = Color(nsColor: .controlBackgroundColor)
    static let sidebarText = Color(nsColor: .labelColor)
    static let sidebarTextMuted = Color(nsColor: .secondaryLabelColor)
    static let sidebarTextFaint = Color(nsColor: .tertiaryLabelColor)
    static let sidebarDivider = Color(nsColor: .separatorColor)
    static let sidebarAccent = brand
    static let sidebarAccentSubtle = brand.opacity(0.1)

    // Main content
    static let pageBg = Color(nsColor: .windowBackgroundColor)
    static let cardBg = Color(nsColor: .controlBackgroundColor)
    static let cardBgAlt = Color(nsColor: .controlBackgroundColor)

    // Text
    static let ink = Color(nsColor: .labelColor)
    static let inkLight = Color(nsColor: .secondaryLabelColor)
    static let inkMuted = Color(nsColor: .tertiaryLabelColor)
    static let inkFaint = Color(nsColor: .quaternaryLabelColor)

    // Accent — brand amber throughout
    static let accent = brand
    static let accentLight = brand.opacity(0.12)
    static let accentSubtle = brand.opacity(0.06)

    // Borders
    static let rule = Color(nsColor: .separatorColor)
    static let ruleBold = Color(nsColor: .gridColor)

    // Provider identity colors
    static let providerOpenAI = Color(nsColor: .systemBlue)
    static let providerGemini = Color(nsColor: .systemIndigo)
    static let providerLocal = Color(nsColor: .systemTeal)
    static let providerParakeet = Color(nsColor: .systemGreen)

    // Heatmap
    static let heatmapEmpty = Color(nsColor: .separatorColor)
    static let heatmapLow = Color(nsColor: .quaternaryLabelColor)
    static let heatmapMedium = Color(nsColor: .tertiaryLabelColor)
    static let heatmapHigh = Color(nsColor: .secondaryLabelColor)
    static let heatmapMax = Color(nsColor: .labelColor).opacity(0.6)

    // Semantic
    static let success = Color(nsColor: .systemGreen)
    static let destructive = Color(nsColor: .systemRed)

    // Typography
    enum Fonts {
        static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }

        static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .rounded)
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
    case dictionary = "Dictionary"
    case recording = "Recording"
    case history = "History"
    case preferences = "Preferences"
    case permissions = "Access"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .providers: return "waveform.circle"
        case .dictionary: return "text.book.closed"
        case .recording: return "keyboard"
        case .history: return "clock.arrow.circlepath"
        case .preferences: return "gearshape"
        case .permissions: return "lock.shield"
        }
    }

    var description: String {
        switch self {
        case .providers: return "Choose your engine and model"
        case .dictionary: return "Names, spellings, and aliases"
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
                // Brand header with amber waveform icon
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DashboardTheme.brand)
                    Text("Whisp")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardTheme.ink)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 14)

                Divider()

                // Clean navigation items — no cluttering description subtitles
                List(DashboardNavItem.allCases, selection: $selectionModel.selectedNav) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 2)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .toolbar(removing: .sidebarToggle)
            .frame(minWidth: 200)
        } detail: {
            if let selectedNav = selectionModel.selectedNav {
                detailView(for: selectedNav)
                    .navigationTitle(selectedNav.rawValue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(DashboardTheme.brand)
                    Text("Select a section")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Choose a category from the sidebar")
                        .font(.subheadline)
                        .foregroundStyle(DashboardTheme.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(DashboardTheme.brand)
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
        case .dictionary:
            DashboardDictionaryView()
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
