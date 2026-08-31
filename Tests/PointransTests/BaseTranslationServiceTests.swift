import XCTest

final class BaseTranslationServiceTests: XCTestCase {
    func testDeviceAIWinsWhenItFinishesWithinDeadline() async throws {
        let service = try makeService(
            deviceAI: DeviceAITranslatorStub(.success("语境翻译")),
            apple: AppleTranslatorStub(.success("苹果翻译")),
            deadline: .seconds(1)
        )

        let result = try await service.translate(request: request(word: "hello", context: "hello there"))

        XCTAssertEqual(result.primaryText, "语境翻译")
        XCTAssertEqual(result.source, .deviceAI)
    }

    func testAIThatMissesDeadlineCannotReplaceAppleResult() async throws {
        let deviceAI = DeviceAITranslatorStub(.cancellationIgnoringDelay("迟到结果", .milliseconds(400)))
        let service = try makeService(
            deviceAI: deviceAI,
            apple: AppleTranslatorStub(.success("苹果翻译")),
            deadline: .milliseconds(5)
        )

        let clock = ContinuousClock()
        let started = clock.now
        let result = try await service.translate(request: request(word: "hello", context: "hello there"))
        let elapsed = started.duration(to: clock.now)
        try await Task.sleep(for: .milliseconds(420))

        XCTAssertEqual(result.primaryText, "苹果翻译")
        XCTAssertEqual(result.source, .appleTranslation)
        XCTAssertLessThan(elapsed, .milliseconds(200))
        let wasCancelled = await deviceAI.wasCancelled
        XCTAssertTrue(wasCancelled)
    }

    func testDeviceAIFailureFallsBackToAppleTranslation() async throws {
        let service = try makeService(
            deviceAI: DeviceAITranslatorStub(.failure),
            apple: AppleTranslatorStub(.success("苹果翻译")),
            deadline: .milliseconds(5)
        )

        let result = try await service.translate(request: request(word: "hello", context: "hello there"))

        XCTAssertEqual(result.primaryText, "苹果翻译")
        XCTAssertEqual(result.source, .appleTranslation)
    }

    func testDictionaryIsFinalFallbackWhenBothBuiltInTranslatorsFail() async throws {
        let service = try makeService(
            deviceAI: DeviceAITranslatorStub(.failure),
            apple: AppleTranslatorStub(.failure),
            deadline: .milliseconds(5)
        )

        let result = try await service.translate(request: request(word: "hello", context: "hello there"))

        XCTAssertEqual(result.meanings.first, "你好")
        XCTAssertEqual(result.source, .dictionary)
    }

    private func makeService(
        deviceAI: any DeviceAITranslating,
        apple: any DeviceTranslating,
        deadline: Duration
    ) throws -> BaseTranslationService {
        BaseTranslationService(
            dictionary: try DictionaryStore(databaseURL: dictionaryURL()),
            deviceAI: deviceAI,
            apple: apple,
            deviceAIDeadline: deadline
        )
    }

    private func dictionaryURL() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Dictionary", withExtension: "sqlite3"))
    }

    private func request(word: String, context: String) -> TranslationRequest {
        TranslationRequest(
            id: UUID(),
            screenPoint: .zero,
            displayID: 0,
            word: word,
            context: context,
            direction: .englishToChinese,
            createdAt: Date()
        )
    }
}

private actor DeviceAITranslatorStub: DeviceAITranslating {
    enum Behavior: Sendable {
        case success(String)
        case cancellationIgnoringDelay(String, Duration)
        case failure
    }
    enum StubError: Error { case unavailable }

    let behavior: Behavior
    private(set) var wasCancelled = false

    init(_ behavior: Behavior) { self.behavior = behavior }

    func translate(request: TranslationRequest) async throws -> String {
        do {
            switch behavior {
            case .success(let value):
                return value
            case .cancellationIgnoringDelay(let value, let duration):
                do {
                    try await Task.sleep(for: duration)
                } catch is CancellationError {
                    wasCancelled = true
                    try? await Task.sleep(for: duration)
                }
                return value
            case .failure:
                throw StubError.unavailable
            }
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }
}

private actor AppleTranslatorStub: DeviceTranslating {
    enum Behavior: Sendable { case success(String), failure }
    enum StubError: Error { case unavailable }
    let behavior: Behavior

    init(_ behavior: Behavior) { self.behavior = behavior }

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        switch behavior {
        case .success(let value): return value
        case .failure: throw StubError.unavailable
        }
    }
}
