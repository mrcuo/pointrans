import XCTest

final class BaseTranslationServiceTests: XCTestCase {
    func testFastLookupDoesNotWaitForDeviceTranslation() async throws {
        let dictionary = try DictionaryStore(databaseURL: dictionaryURL())
        let device = DeviceTranslatorStub(result: .success("你好"))
        let service = BaseTranslationService(dictionary: dictionary, apple: device)

        let base = try await service.translate(
            word: "hello",
            context: "hello there",
            direction: .englishToChinese
        )

        XCTAssertEqual(base.meanings.first, "你好")
        XCTAssertNil(base.deviceTranslation)
        let callCount = await device.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testDeviceTranslationEnrichesDictionaryResult() async throws {
        let dictionary = try DictionaryStore(databaseURL: dictionaryURL())
        let device = DeviceTranslatorStub(result: .success("拉动"))
        let service = BaseTranslationService(dictionary: dictionary, apple: device)
        let base = BaseTranslation(
            meanings: ["拉取"],
            deviceTranslation: nil,
            phonetic: nil,
            pinyin: nil,
            source: .dictionary
        )

        let enriched = try await service.enrich(
            base,
            word: "pulling",
            context: "She kept pulling the thread.",
            direction: .englishToChinese
        )

        XCTAssertEqual(enriched.deviceTranslation, "拉动")
        XCTAssertEqual(enriched.source, .dictionaryAndApple)
        let callCount = await device.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testMissingLanguagePackNeverBlocksExistingDictionaryMeaning() async throws {
        let dictionary = try DictionaryStore(databaseURL: dictionaryURL())
        let device = DeviceTranslatorStub(result: .failure(.unavailable))
        let service = BaseTranslationService(dictionary: dictionary, apple: device)
        let base = BaseTranslation(
            meanings: ["离线释义"],
            deviceTranslation: nil,
            phonetic: nil,
            pinyin: nil,
            source: .dictionary
        )

        let result = try await service.enrich(
            base,
            word: "word",
            context: "word in context",
            direction: .englishToChinese
        )

        XCTAssertEqual(result, base)
    }

    private func dictionaryURL() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Dictionary", withExtension: "sqlite3"))
    }
}

private actor DeviceTranslatorStub: DeviceTranslating {
    enum StubError: Error, Sendable { case unavailable }

    let result: Result<String, StubError>
    private(set) var callCount = 0

    init(result: Result<String, StubError>) {
        self.result = result
    }

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        callCount += 1
        return try result.get()
    }
}
