import SwiftUI

internal struct PersonalDictionaryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: PersonalDictionaryStore

    @State private var draftEntries: [DraftEntry]
    @State private var saveError: String?

    init(store: PersonalDictionaryStore = .shared) {
        self.store = store
        _draftEntries = State(initialValue: store.entries.map(DraftEntry.init))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerPanel

                if let saveError {
                    errorBanner(saveError)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }

                tableContainer
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                footerBar
            }
            .background(DashboardTheme.pageBg)
            .navigationTitle("Personal Dictionary")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addEntry()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add term")
                }
            }
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var headerPanel: some View {
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Manage Preferred Spellings")
                    .font(DashboardTheme.Fonts.serif(24, weight: .semibold))
                    .foregroundStyle(DashboardTheme.ink)

                Text(
                    "Add one row per preferred spelling, then list the aliases Whisp should normalize into it."
                )
                .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                .foregroundStyle(DashboardTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DashboardTheme.Spacing.md)

            Text(
                draftEntries.isEmpty
                    ? "No terms"
                    : "\(draftEntries.count) \(draftEntries.count == 1 ? "term" : "terms")"
            )
            .font(DashboardTheme.Fonts.mono(11, weight: .semibold))
            .foregroundStyle(DashboardTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(DashboardTheme.accentLight))
        }
        .padding(20)
    }

    private var tableContainer: some View {
        VStack(spacing: 0) {
            tableHeader

            Divider()

            if draftEntries.isEmpty {
                emptyTableState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($draftEntries) { $entry in
                            rowView(entry: $entry)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DashboardTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DashboardTheme.rule.opacity(0.6), lineWidth: 1)
        )
    }

    private var footerBar: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            Text(
                draftEntries.isEmpty
                    ? "Use the plus button to add your first term."
                    : "Use the plus button to add rows and the minus button to remove them."
            )
            .font(DashboardTheme.Fonts.sans(12, weight: .regular))
            .foregroundStyle(DashboardTheme.inkMuted)

            Spacer()

            Button {
                addEntry()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DashboardTheme.accent)
            .help(draftEntries.isEmpty ? "Add first term" : "Add another term")
        }
        .padding(20)
        .background(.bar)
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("Preferred spelling")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Aliases")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(" ")
                .frame(width: 28)
        }
        .font(DashboardTheme.Fonts.mono(11, weight: .semibold))
        .foregroundStyle(DashboardTheme.inkMuted)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(DashboardTheme.cardBgAlt)
    }

    private var emptyTableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DashboardTheme.inkFaint)

            Text("No terms yet")
                .font(DashboardTheme.Fonts.serif(18, weight: .semibold))
                .foregroundStyle(DashboardTheme.ink)

            Text("Press the plus button to add a preferred spelling and its aliases.")
                .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                .foregroundStyle(DashboardTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.horizontal, 20)
    }

    private func rowView(entry: Binding<DraftEntry>) -> some View {
        let draft = entry.wrappedValue

        return HStack(alignment: .center, spacing: 12) {
            TextField("Whisp", text: entry.preferredText)
                .textFieldStyle(.roundedBorder)
                .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                .accessibilityLabel("Preferred spelling")
                .accessibilityHint("The exact text Whisp should use in the final transcript.")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(
                "wisp, whispp",
                text: entry.aliasesText,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .font(DashboardTheme.Fonts.sans(13, weight: .regular))
            .lineLimit(1...2)
            .accessibilityLabel("Aliases")
            .accessibilityHint("Comma-separated variants that should normalize to the preferred spelling.")
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                removeEntry(id: draft.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(nsColor: .systemRed))
            .help("Remove term")
            .accessibilityLabel("Remove term")
            .frame(width: 28)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))

            Text(text)
                .font(DashboardTheme.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemRed))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.1))
        )
    }

    private func addEntry() {
        saveError = nil
        draftEntries.append(DraftEntry(preferredText: "", aliasesText: ""))
    }

    private func removeEntry(id: UUID) {
        saveError = nil
        draftEntries.removeAll { $0.id == id }
    }

    private func save() {
        saveError = nil

        let hasIncompleteEntry = draftEntries.contains {
            normalized($0.preferredText).isEmpty && !normalized($0.aliasesText).isEmpty
        }
        if hasIncompleteEntry {
            saveError = "Each term needs a preferred spelling before it can be saved."
            return
        }

        let entries = draftEntries.map {
            PersonalDictionaryEntry(
                id: $0.id,
                preferredText: $0.preferredText,
                aliases: parseAliases($0.aliasesText)
            )
        }
        guard store.replaceAll(entries) else {
            saveError = "Couldn't save your personal dictionary. Check disk access and try again."
            return
        }
        dismiss()
    }

    private func parseAliases(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DraftEntry: Identifiable {
    let id: UUID
    var preferredText: String
    var aliasesText: String

    init(id: UUID = UUID(), preferredText: String, aliasesText: String) {
        self.id = id
        self.preferredText = preferredText
        self.aliasesText = aliasesText
    }

    init(_ entry: PersonalDictionaryEntry) {
        self.id = entry.id
        self.preferredText = entry.preferredText
        self.aliasesText = entry.aliases.joined(separator: ", ")
    }
}
