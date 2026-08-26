import CoreGraphics
import XCTest

final class ContextAnalyzerRouterTests: XCTestCase {
    func testAvailableDeviceModelReturnsOnDeviceWithoutCloudCall() async throws {
        let cloud = CloudAnalyzerSpy(result: .success(cloudResult()))
        let router = ContextAnalyzerRouter(
            apple: DeviceAnalyzerStub(result: .success(insight("device"))),
            cloud: cloud
        )

        let result = try await router.analyze(request: request(), base: base())
        XCTAssertEqual(result.route, .onDevice)
        XCTAssertEqual(result.insight.contextualMeaning, "device")
        let callCount = await cloud.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testUnavailableAndTransientDeviceErrorsFallBackToCloud() async throws {
        for error in [ContextAnalyzerError.unavailable, .transient] {
            let cloud = CloudAnalyzerSpy(result: .success(cloudResult()))
            let router = ContextAnalyzerRouter(
                apple: DeviceAnalyzerStub(result: .failure(error)),
                cloud: cloud
            )

            let result = try await router.analyze(request: request(), base: base())
            XCTAssertEqual(result.route, .cloud)
            let callCount = await cloud.callCount()
            XCTAssertEqual(callCount, 1)
        }
    }

    func testSafetyRefusalDoesNotSendContextToCloud() async {
        let cloud = CloudAnalyzerSpy(result: .success(cloudResult()))
        let router = ContextAnalyzerRouter(
            apple: DeviceAnalyzerStub(result: .failure(.safetyRefusal)),
            cloud: cloud
        )

        do {
            _ = try await router.analyze(request: request(), base: base())
            XCTFail("Expected a safety refusal")
        } catch let error as ContextAnalyzerError {
            XCTAssertEqual(error, .safetyRefusal)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await cloud.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testCancellationDoesNotFallBackAndRemainsCancellation() async {
        let cloud = CloudAnalyzerSpy(result: .success(cloudResult()))
        let router = ContextAnalyzerRouter(
            apple: DeviceAnalyzerStub(result: .failure(.cancelled)),
            cloud: cloud
        )

        do {
            _ = try await router.analyze(request: request(), base: base())
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await cloud.callCount()
        XCTAssertEqual(callCount, 0)
    }

    private func request() -> TranslationRequest {
        TranslationRequest(
            id: UUID(),
            screenPoint: CGPoint(x: 100, y: 100),
            displayID: CGMainDisplayID(),
            word: "pulling",
            context: "She kept pulling the thread.",
            direction: .englishToChinese,
            createdAt: Date()
        )
    }

    private func base() -> BaseTranslation {
        BaseTranslation(meanings: ["拉动"], deviceTranslation: nil, phonetic: nil, pinyin: nil, source: .dictionary)
    }

    private func insight(_ meaning: String) -> ContextInsight {
        ContextInsight(contextualMeaning: meaning, partOfSpeech: "verb", explanation: "explanation", contextTranslation: nil)
    }

    private func cloudResult() -> InsightResult {
        InsightResult(insight: insight("cloud"), route: .cloud, remainingCloudQuota: 29, quotaResetAt: nil)
    }
}

private struct DeviceAnalyzerStub: DeviceContextAnalyzing {
    let result: Result<ContextInsight, ContextAnalyzerError>

    func analyze(request: TranslationRequest, base: BaseTranslation) async throws -> ContextInsight {
        try result.get()
    }
}

private actor CloudAnalyzerSpy: CloudContextAnalyzing {
    private let result: Result<InsightResult, ContextAnalyzerError>
    private var calls = 0

    init(result: Result<InsightResult, ContextAnalyzerError>) {
        self.result = result
    }

    func analyze(request: TranslationRequest, base: BaseTranslation) async throws -> InsightResult {
        calls += 1
        return try result.get()
    }

    func callCount() -> Int { calls }
}
