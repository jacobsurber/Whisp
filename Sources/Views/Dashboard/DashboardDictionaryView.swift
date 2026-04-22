import SwiftUI

internal struct DashboardDictionaryView: View {
    @AppStorage(AppDefaults.Keys.personalDictionaryEnabled) private var personalDictionaryEnabled = true
    @AppStorage(AppDefaults.Keys.semanticCorrectionMode) private var semanticCorrectionModeRaw = AppDefaults
        .defaultSemanticCorrectionMode.rawValue

    @State private var personalDictionaryStore = PersonalDictionaryStore.shared
    @State private var showEditorSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                heroCard
                metricsSection
                previewSection
                workflowSection

                if let storagePath = personalDictionaryStore.storagePath {
                    storageSection(path: storagePath)
                }
            }
            .padding(DashboardTheme.Spacing.lg)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .background(DashboardTheme.pageBg)
        .sheet(isPresented: $showEditorSheet) {
            PersonalDictionaryEditorSheet(store: personalDictionaryStore)
        }
    }

    private var semanticCorrectionMode: SemanticCorrectionMode {
        SemanticCorrectionMode(rawValue: semanticCorrectionModeRaw) ?? .off
    }

    private var sortedEntries: [PersonalDictionaryEntry] {
        personalDictionaryStore.entries.sorted {
            $0.preferredText.localizedCaseInsensitiveCompare($1.preferredText) == .orderedAscending
        }
    }

    private var entryCount: Int {
        sortedEntries.count
    }

    private var aliasCount: Int {
        sortedEntries.reduce(0) { partialResult, entry in
            partialResult + entry.aliases.count
        }
    }

    private var previewEntries: [PersonalDictionaryEntry] {
        Array(sortedEntries.prefix(4))
    }

    private var manageButtonTitle: String {
        entryCount == 0 ? "Add First Terms…" : "Manage Terms…"
    }

    private var engineSummaryText: String {
        if semanticCorrectionMode == .off {
            return "Turn on semantic correction in Transcription to activate dictionary replacements."
        }

        if !personalDictionaryEnabled {
            return "Your terms are stored, but Whisp will not apply them until this tab is enabled."
        }

        switch semanticCorrectionMode {
        case .cloud:
            return "Preferred spellings are applied after cloud correction finishes."
        case .localMLX:
            return "Preferred spellings are applied after on-device MLX correction finishes."
        case .off:
            return "Turn on semantic correction in Transcription to activate dictionary replacements."
        }
    }

    private var heroCard: some View {
        let status = personalDictionaryStatus()

        return dictionaryCard {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
                HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(DashboardTheme.accentLight)
                                    .frame(width: 42, height: 42)

                                Image(systemName: "text.book.closed.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(DashboardTheme.accent)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Teach Whisp Your Vocabulary")
                                    .font(DashboardTheme.Fonts.serif(26, weight: .semibold))
                                    .foregroundStyle(DashboardTheme.ink)

                                Text(
                                    "Names, brands, acronyms, and internal language stay consistent after cleanup."
                                )
                                .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                                .foregroundStyle(DashboardTheme.inkLight)
                            }
                        }

                        Text(
                            "The dictionary runs after semantic correction, so transcripts can stay natural while still landing on exact spellings in the final text."
                        )
                        .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                        .foregroundStyle(DashboardTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: DashboardTheme.Spacing.md)

                    statusBadge(
                        text: status.text,
                        symbol: status.symbol,
                        color: status.color
                    )
                }

                Divider()

                HStack(alignment: .center, spacing: DashboardTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dictionary Engine")
                            .font(DashboardTheme.Fonts.sans(13, weight: .semibold))
                            .foregroundStyle(DashboardTheme.ink)

                        Text(engineSummaryText)
                            .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                            .foregroundStyle(DashboardTheme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: DashboardTheme.Spacing.md)

                    Toggle("Enabled", isOn: $personalDictionaryEnabled)
                        .toggleStyle(.switch)

                    Button(manageButtonTitle) {
                        showEditorSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var metricsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DashboardTheme.Spacing.md) {
                metricTile(
                    title: "Terms",
                    value: "\(entryCount)",
                    detail: entryCount == 1 ? "preferred spelling" : "preferred spellings",
                    symbol: "character.book.closed"
                )

                metricTile(
                    title: "Aliases",
                    value: "\(aliasCount)",
                    detail: aliasCount == 1 ? "exact variant" : "exact variants",
                    symbol: "captions.bubble"
                )

                metricTile(
                    title: "Correction",
                    value: semanticCorrectionMode == .off ? "Off" : semanticCorrectionMode.displayName,
                    detail: semanticCorrectionMode == .cloud ? "provider-assisted" : "finalization stage",
                    symbol: semanticCorrectionMode == .cloud ? "cloud.fill" : "wand.and.stars"
                )

                metricTile(
                    title: "Scope",
                    value: "Global",
                    detail: "shared across every app",
                    symbol: "globe"
                )
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if previewEntries.isEmpty {
            dictionaryCard {
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
                    HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start With the Words You Correct Most")
                                .font(DashboardTheme.Fonts.serif(20, weight: .semibold))
                                .foregroundStyle(DashboardTheme.ink)

                            Text(
                                "Good first entries are people, products, acronyms, and project vocabulary that generic models flatten."
                            )
                            .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                            .foregroundStyle(DashboardTheme.inkMuted)
                        }

                        Spacer(minLength: DashboardTheme.Spacing.md)

                        Button("Add Your First Term") {
                            showEditorSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DashboardTheme.Spacing.md) {
                            sampleCard(preferredText: "Whisp", aliases: ["wisp", "whispp"])
                            sampleCard(preferredText: "OpenAI", aliases: ["open ai"])
                        }

                        VStack(spacing: DashboardTheme.Spacing.md) {
                            sampleCard(preferredText: "Whisp", aliases: ["wisp", "whispp"])
                            sampleCard(preferredText: "OpenAI", aliases: ["open ai"])
                        }
                    }
                }
            }
        } else {
            dictionaryCard {
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
                    HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Glossary Preview")
                                .font(DashboardTheme.Fonts.serif(20, weight: .semibold))
                                .foregroundStyle(DashboardTheme.ink)

                            Text("A quick scan of the spellings Whisp will enforce after correction.")
                                .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                                .foregroundStyle(DashboardTheme.inkMuted)
                        }

                        Spacer(minLength: DashboardTheme.Spacing.md)

                        if entryCount > previewEntries.count {
                            Text("+\(entryCount - previewEntries.count) more")
                                .font(DashboardTheme.Fonts.mono(11, weight: .semibold))
                                .foregroundStyle(DashboardTheme.inkMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(DashboardTheme.accentSubtle))
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(previewEntries) { entry in
                            previewRow(entry)
                        }
                    }
                }
            }
        }
    }

    private var workflowSection: some View {
        dictionaryCard {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
                HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What Happens During Transcription")
                            .font(DashboardTheme.Fonts.serif(20, weight: .semibold))
                            .foregroundStyle(DashboardTheme.ink)

                        Text("The dictionary is a finishing pass, not an aggressive rewrite.")
                            .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                            .foregroundStyle(DashboardTheme.inkMuted)
                    }

                    Spacer(minLength: DashboardTheme.Spacing.md)

                    if semanticCorrectionMode == .cloud && personalDictionaryEnabled && entryCount > 0 {
                        Text("Cloud provider may see dictionary terms")
                            .font(DashboardTheme.Fonts.mono(11, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .systemOrange).opacity(0.12))
                            )
                    }
                }

                VStack(spacing: 12) {
                    workflowRow(
                        number: "01",
                        title: "Capture exact terms",
                        detail:
                            "Add the spellings you want preserved, plus the variants people actually say or dictate."
                    )

                    workflowRow(
                        number: "02",
                        title: semanticCorrectionMode == .off
                            ? "Enable correction" : "Clean the transcript",
                        detail: semanticCorrectionMode == .off
                            ? "Turn on semantic correction in Transcription before dictionary replacements can run."
                            : "Whisp fixes grammar and punctuation first, so the dictionary does not fight the cleanup pass."
                    )

                    workflowRow(
                        number: "03",
                        title: "Lock the final spelling",
                        detail:
                            "Configured names, brands, and acronyms are normalized to the preferred form in the final result.",
                        showsConnector: false
                    )
                }
            }
        }
    }

    private func storageSection(path: String) -> some View {
        dictionaryCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Storage")
                    .font(DashboardTheme.Fonts.sans(13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.ink)

                Text("Whisp stores the glossary as a global JSON file in Application Support.")
                    .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)

                Text(PathFormatting.displayHomeRelativePath(path))
                    .font(DashboardTheme.Fonts.mono(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkLight)
                    .textSelection(.enabled)
            }
        }
    }

    private func metricTile(
        title: String,
        value: String,
        detail: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(DashboardTheme.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(DashboardTheme.inkMuted)

            Text(value)
                .font(DashboardTheme.Fonts.serif(24, weight: .semibold))
                .foregroundStyle(DashboardTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                .foregroundStyle(DashboardTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DashboardTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.55), lineWidth: 1)
        )
    }

    private func sampleCard(preferredText: String, aliases: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preferredText)
                .font(DashboardTheme.Fonts.serif(18, weight: .semibold))
                .foregroundStyle(DashboardTheme.ink)

            Text("Heard as: \(aliases.joined(separator: " • "))")
                .font(DashboardTheme.Fonts.mono(12, weight: .regular))
                .foregroundStyle(DashboardTheme.inkLight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DashboardTheme.accentSubtle)
        )
    }

    private func previewRow(_ entry: PersonalDictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.preferredText)
                    .font(DashboardTheme.Fonts.serif(18, weight: .semibold))
                    .foregroundStyle(DashboardTheme.ink)

                Spacer()

                Text(entry.aliases.isEmpty ? "preferred only" : "\(entry.aliases.count) aliases")
                    .font(DashboardTheme.Fonts.mono(11, weight: .semibold))
                    .foregroundStyle(DashboardTheme.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DashboardTheme.cardBgAlt))
            }

            if entry.aliases.isEmpty {
                Text("No aliases yet. Whisp keeps this preferred spelling stable when it already appears.")
                    .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Heard as: \(entry.aliases.joined(separator: " • "))")
                    .font(DashboardTheme.Fonts.mono(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DashboardTheme.cardBgAlt)
        )
    }

    private func workflowRow(
        number: String,
        title: String,
        detail: String,
        showsConnector: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(number)
                    .font(DashboardTheme.Fonts.mono(11, weight: .semibold))
                    .foregroundStyle(DashboardTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(DashboardTheme.accentLight)
                    )

                if showsConnector {
                    Rectangle()
                        .fill(DashboardTheme.rule.opacity(0.8))
                        .frame(width: 1, height: 34)
                        .padding(.top, 6)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DashboardTheme.Fonts.sans(14, weight: .semibold))
                    .foregroundStyle(DashboardTheme.ink)

                Text(detail)
                    .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private func dictionaryCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(DashboardTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
    }

    private func statusBadge(text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(DashboardTheme.Fonts.sans(12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private func personalDictionaryStatus() -> (text: String, symbol: String, color: Color) {
        if semanticCorrectionMode == .off {
            return (
                "Inactive while semantic correction is off.",
                "pause.circle.fill",
                Color(nsColor: .systemOrange)
            )
        }

        if !personalDictionaryEnabled {
            return ("Personal dictionary disabled.", "xmark.circle.fill", Color.secondary)
        }

        if entryCount == 0 {
            return ("No terms configured yet.", "text.badge.plus", Color.secondary)
        }

        let countLabel = entryCount == 1 ? "1 term ready." : "\(entryCount) terms ready."
        return (countLabel, "checkmark.circle.fill", Color(nsColor: .systemGreen))
    }
}

#Preview {
    DashboardDictionaryView()
        .frame(width: 900, height: 700)
}
