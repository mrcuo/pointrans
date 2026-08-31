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
        let service = BaseTranslationService(
            dictionary: store,
            deviceAI: UnavailableDictionaryTestDeviceAI(),
            apple: UnavailableDictionaryTestAppleTranslation(),
            deviceAIDeadline: .milliseconds(5)
        )

        let result = try await service.translate(request: TranslationRequest(
            id: UUID(),
            screenPoint: .zero,
            displayID: 0,
            word: "pulling",
            context: "She kept pulling the thread until the knot came loose.",
            direction: .englishToChinese,
            createdAt: Date()
        ))

        XCTAssertEqual(result.meanings.first, "拉取")
        XCTAssertTrue(result.meanings.contains("套头"))
    }
}

private actor UnavailableDictionaryTestDeviceAI: DeviceAITranslating {
    func translate(request: TranslationRequest) async throws -> String {
        throw TranslationFailure.translationUnavailable
    }
}

private actor UnavailableDictionaryTestAppleTranslation: DeviceTranslating {
    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        throw TranslationFailure.translationUnavailable
    }
}
