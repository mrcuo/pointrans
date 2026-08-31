import CoreGraphics
import XCTest

final class HybridTextExtractorTests: XCTestCase {
    func testAccessibilityResultWinsWithoutStartingOCR() async throws {
        let expected = extraction(word: "accessible", source: .accessibility)
        let accessibility = ExtractorStub(behavior: .success(expected))
        let ocr = ExtractorStub(behavior: .success(extraction(word: "ocr", source: .ocr)))
        let hybrid = HybridTextExtractor(accessibility: accessibility, ocr: ocr)

        let result = try await hybrid.extract(at: .zero, displayID: 1)

        XCTAssertEqual(result, expected)
        let accessibilityCalls = await accessibility.callCount
        let ocrCalls = await ocr.callCount
        XCTAssertEqual(accessibilityCalls, 1)
        XCTAssertEqual(ocrCalls, 0)
    }

    func testUnsupportedAccessibilityFallsBackToOCRAtTheSameAnchor() async throws {
        let point = CGPoint(x: -320, y: 840)
        let accessibility = ExtractorStub(behavior: .failure)
        let expected = extraction(word: "fallback", source: .ocr, point: point)
        let ocr = ExtractorStub(behavior: .success(expected))
        let hybrid = HybridTextExtractor(accessibility: accessibility, ocr: ocr)

        let result = try await hybrid.extract(at: point, displayID: 42)

        XCTAssertEqual(result, expected)
        let capturedPoint = await ocr.lastPoint
        let capturedDisplayID = await ocr.lastDisplayID
        XCTAssertEqual(capturedPoint, point)
        XCTAssertEqual(capturedDisplayID, 42)
    }

    func testCancellationNeverStartsOCRFallback() async {
        let accessibility = ExtractorStub(behavior: .cancelled)
        let ocr = ExtractorStub(behavior: .success(extraction(word: "ocr", source: .ocr)))
        let hybrid = HybridTextExtractor(accessibility: accessibility, ocr: ocr)

        do {
            _ = try await hybrid.extract(at: .zero, displayID: 1)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let ocrCalls = await ocr.callCount
        XCTAssertEqual(ocrCalls, 0)
    }

    private func extraction(
        word: String,
        source: ExtractionSource,
        point: CGPoint = .zero
    ) -> ExtractionResult {
        ExtractionResult(
            word: word,
            context: "\(word) in context",
            bounds: CGRect(origin: point, size: CGSize(width: 40, height: 18)),
            confidence: 1,
            source: source
        )
    }
}

private actor ExtractorStub: TextExtracting {
    enum Behavior: Sendable {
        case success(ExtractionResult)
        case failure
        case cancelled
    }
    enum StubError: Error, Sendable { case unavailable }

    let behavior: Behavior
    private(set) var callCount = 0
    private(set) var lastPoint: CGPoint?
    private(set) var lastDisplayID: CGDirectDisplayID?

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func extract(
        at point: CGPoint,
        displayID: CGDirectDisplayID
    ) async throws -> ExtractionResult {
        callCount += 1
        lastPoint = point
        lastDisplayID = displayID
        return switch behavior {
        case .success(let value): value
        case .failure: throw StubError.unavailable
        case .cancelled: throw CancellationError()
        }
    }
}
