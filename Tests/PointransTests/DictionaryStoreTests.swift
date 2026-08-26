import XCTest

final class DictionaryStoreTests: XCTestCase {
    func testBundledDictionaryLooksUpBothDirectionsWithoutLoadingCorpus() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Dictionary", withExtension: "sqlite3"))
        let store = try DictionaryStore(databaseURL: url)

        let english = try await store.lookup("Hello", direction: .englishToChinese)
        XCTAssertEqual(english?.meanings.first, "你好")

        let chinese = try await store.lookup("翻译", direction: .chineseToEnglish)
        XCTAssertTrue(chinese?.meanings.contains("translation") == true)
        XCTAssertTrue(chinese?.meanings.contains("translate") == true)
    }

    func testUnknownAndBlankTermsReturnNil() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Dictionary", withExtension: "sqlite3"))
        let store = try DictionaryStore(databaseURL: url)

        let blank = try await store.lookup("  ", direction: .englishToChinese)
        let unknown = try await store.lookup("pointrans-nonexistent-token", direction: .englishToChinese)
        XCTAssertNil(blank)
        XCTAssertNil(unknown)
    }

    func testContextualVerbInflectionPrefersLemmaMeaning() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Dictionary", withExtension: "sqlite3"))
        let store = try DictionaryStore(databaseURL: url)
        let service = BaseTranslationService(dictionary: store)

        let result = try await service.translate(
            word: "pulling",
            context: "She kept pulling the thread until the knot came loose.",
            direction: .englishToChinese
        )

        XCTAssertEqual(result.meanings.first, "拉取")
        XCTAssertTrue(result.meanings.contains("套头"))
    }
}
