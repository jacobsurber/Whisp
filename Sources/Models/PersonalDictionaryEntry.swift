import Foundation

internal struct PersonalDictionaryEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var preferredText: String
    var aliases: [String]

    init(id: UUID = UUID(), preferredText: String, aliases: [String] = []) {
        self.id = id
        self.preferredText = preferredText
        self.aliases = aliases
    }
}

internal struct PersonalDictionaryDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var entries: [PersonalDictionaryEntry]

    init(version: Int = PersonalDictionaryDocument.currentVersion, entries: [PersonalDictionaryEntry] = []) {
        self.version = version
        self.entries = entries
    }
}

internal struct PersonalDictionaryRule: Equatable, Sendable {
    let preferredText: String
    let aliases: [String]
}

internal struct PersonalDictionarySnapshot: Equatable, Sendable {
    let rules: [PersonalDictionaryRule]

    static let empty = PersonalDictionarySnapshot(rules: [])

    var isEmpty: Bool {
        rules.isEmpty
    }
}

internal protocol PersonalDictionaryProviding {
    func snapshot() -> PersonalDictionarySnapshot
}
