import CoreGraphics
import Foundation

struct HybridTextExtractor: TextExtracting, Sendable {
    private let accessibility: any TextExtracting
    private let ocr: any TextExtracting

    init(
        accessibility: any TextExtracting = AccessibilityTextExtractor(),
        ocr: any TextExtracting = OCRTextExtractor()
    ) {
        self.accessibility = accessibility
        self.ocr = ocr
    }

    func extract(
        at point: CGPoint,
        displayID: CGDirectDisplayID,
        direction: TranslationDirection
    ) async throws -> ExtractionResult {
        do {
            return try await accessibility.extract(at: point, displayID: displayID, direction: direction)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return try await ocr.extract(at: point, displayID: displayID, direction: direction)
        }
    }
}
