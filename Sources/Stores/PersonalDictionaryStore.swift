import Foundation
import Observation

@Observable
internal final class PersonalDictionaryStore: PersonalDictionaryProviding {
    static let shared = PersonalDictionaryStore()

    private(set) var entries: [PersonalDictionaryEntry]

    private let fileManager: FileManager
    private let storageURL: URL?

    init(fileManager: FileManager = .default, storageURL: URL? = nil) {
        self.fileManager = fileManager
        if let storageURL {
            self.storageURL = storageURL
        } else {
            self.storageURL =
                try? fileManager
                .url(
                    for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
                )
                .appendingPathComponent("Whisp/personal-dictionary.json", isDirectory: false)
        }

        self.entries = []
        loadFromDiskIfNeeded()
    }

    var storagePath: String? {
        storageURL?.path
    }

    @discardableResult
    func replaceAll(_ entries: [PersonalDictionaryEntry]) -> Bool {
        let sanitizedEntries = Self.sanitized(entries)
        guard persist(sanitizedEntries) else {
            return false
        }

        self.entries = sanitizedEntries
        return true
    }

    func snapshot() -> PersonalDictionarySnapshot {
        let rules =
            entries
            .map { PersonalDictionaryRule(preferredText: $0.preferredText, aliases: $0.aliases) }
            .sorted {
                $0.preferredText.localizedCaseInsensitiveCompare($1.preferredText) == .orderedAscending
            }
        return PersonalDictionarySnapshot(rules: rules)
    }

    private func loadFromDiskIfNeeded() {
        guard let storageURL,
            fileManager.fileExists(atPath: storageURL.path)
        else {
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)

            if let decoded = try? JSONDecoder().decode(PersonalDictionaryDocument.self, from: data) {
                entries = Self.sanitized(decoded.entries)
                return
            }

            if let decoded = try? JSONDecoder().decode([PersonalDictionaryEntry].self, from: data) {
                entries = Self.sanitized(decoded)
            }
        } catch {
            entries = []
        }
    }

    private func persist(_ entries: [PersonalDictionaryEntry]) -> Bool {
        guard let storageURL else { return false }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(
                PersonalDictionaryDocument(entries: entries)
            )
            let dir = storageURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: storageURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static func sanitized(_ entries: [PersonalDictionaryEntry]) -> [PersonalDictionaryEntry] {
        var mergedEntries: [PersonalDictionaryEntry] = []
        var indexByPreferredKey: [String: Int] = [:]
        var claimedKeys: Set<String> = []

        for entry in entries {
            guard let clean = sanitizedEntry(entry) else { continue }

            let key = canonicalKey(clean.preferredText)
            if let existingIndex = indexByPreferredKey[key] {
                let existingEntry = mergedEntries[existingIndex]
                let existingKeys = Set(
                    ([existingEntry.preferredText] + existingEntry.aliases).map(canonicalKey))
                let allowedAliases = clean.aliases.filter {
                    let aliasKey = canonicalKey($0)
                    return !claimedKeys.contains(aliasKey) || existingKeys.contains(aliasKey)
                }
                let mergedEntry = merged(
                    existingEntry,
                    with: PersonalDictionaryEntry(
                        id: clean.id,
                        preferredText: clean.preferredText,
                        aliases: allowedAliases
                    )
                )
                mergedEntries[existingIndex] = mergedEntry
                for alias in allowedAliases {
                    claimedKeys.insert(canonicalKey(alias))
                }
            } else {
                guard !claimedKeys.contains(key) else { continue }

                let allowedAliases = clean.aliases.filter {
                    !claimedKeys.contains(canonicalKey($0))
                }
                let acceptedEntry = PersonalDictionaryEntry(
                    id: clean.id,
                    preferredText: clean.preferredText,
                    aliases: allowedAliases
                )

                indexByPreferredKey[key] = mergedEntries.count
                mergedEntries.append(acceptedEntry)
                claimedKeys.insert(key)
                for alias in allowedAliases {
                    claimedKeys.insert(canonicalKey(alias))
                }
            }
        }

        return mergedEntries
    }

    private static func sanitizedEntry(_ entry: PersonalDictionaryEntry) -> PersonalDictionaryEntry? {
        let preferredText = normalizedPhrase(entry.preferredText)
        guard !preferredText.isEmpty else { return nil }

        var seenAliases: Set<String> = [canonicalKey(preferredText)]
        var aliases: [String] = []

        for alias in entry.aliases {
            let cleanAlias = normalizedPhrase(alias)
            guard !cleanAlias.isEmpty else { continue }

            let key = canonicalKey(cleanAlias)
            guard !seenAliases.contains(key) else { continue }

            seenAliases.insert(key)
            aliases.append(cleanAlias)
        }

        return PersonalDictionaryEntry(id: entry.id, preferredText: preferredText, aliases: aliases)
    }

    private static func merged(_ lhs: PersonalDictionaryEntry, with rhs: PersonalDictionaryEntry)
        -> PersonalDictionaryEntry
    {
        var seenAliases = Set<String>()
        var aliases: [String] = []

        for alias in lhs.aliases + rhs.aliases {
            let key = canonicalKey(alias)
            guard !seenAliases.contains(key) else { continue }
            seenAliases.insert(key)
            aliases.append(alias)
        }

        return PersonalDictionaryEntry(id: lhs.id, preferredText: lhs.preferredText, aliases: aliases)
    }

    private static func normalizedPhrase(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func canonicalKey(_ value: String) -> String {
        normalizedPhrase(value)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
