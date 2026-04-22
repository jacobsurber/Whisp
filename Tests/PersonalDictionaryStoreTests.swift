import XCTest

@testable import Whisp

final class PersonalDictionaryStoreTests: XCTestCase {
    private var tempURL: URL!
    private var store: PersonalDictionaryStore!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        store = PersonalDictionaryStore(fileManager: .default, storageURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        store = nil
        tempURL = nil
        super.tearDown()
    }

    func testReplaceAllSanitizesEntriesAndMergesDuplicates() {
        XCTAssertTrue(
            store.replaceAll([
                PersonalDictionaryEntry(preferredText: "  Whisp  ", aliases: [" wisp ", "whispp", "Whisp"]),
                PersonalDictionaryEntry(preferredText: "whisp", aliases: ["wisp"]),
                PersonalDictionaryEntry(preferredText: "", aliases: ["ignored"]),
            ]))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.preferredText, "Whisp")
        XCTAssertEqual(store.entries.first?.aliases, ["wisp", "whispp"])
    }

    func testSnapshotReflectsPersistedEntries() {
        XCTAssertTrue(
            store.replaceAll([
                PersonalDictionaryEntry(preferredText: "OpenAI", aliases: ["open ai"]),
                PersonalDictionaryEntry(preferredText: "Whisp", aliases: ["wisp"]),
            ]))

        let reloaded = PersonalDictionaryStore(fileManager: .default, storageURL: tempURL)
        let snapshot = reloaded.snapshot()

        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(snapshot.rules.map(\.preferredText), ["OpenAI", "Whisp"])
    }

    func testInvalidJSONFallsBackToEmptyDictionary() throws {
        try "not valid json".write(to: tempURL, atomically: true, encoding: .utf8)

        let reloaded = PersonalDictionaryStore(fileManager: .default, storageURL: tempURL)

        XCTAssertTrue(reloaded.entries.isEmpty)
        XCTAssertTrue(reloaded.snapshot().isEmpty)
    }

    func testReplaceAllPreservesDiacriticOnlyAliases() {
        XCTAssertTrue(
            store.replaceAll([
                PersonalDictionaryEntry(preferredText: "José", aliases: ["Jose"])
            ]))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.aliases, ["Jose"])
    }

    func testReplaceAllDropsConflictingAliasesAndPreferredTerms() {
        XCTAssertTrue(
            store.replaceAll([
                PersonalDictionaryEntry(preferredText: "OpenAI", aliases: ["open ai"]),
                PersonalDictionaryEntry(preferredText: "Open AI", aliases: ["open ai", "open-ai"]),
            ]))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.preferredText, "OpenAI")
        XCTAssertEqual(store.entries.first?.aliases, ["open ai"])
    }
}
