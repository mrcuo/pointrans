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
        displayID: CGDirectDisplayID
    ) async throws -> ExtractionResult {
        let accessibilityFailure: ExtractionError
        do {
            return try await accessibility.extract(at: point, displayID: displayID)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ExtractionError {
            accessibilityFailure = error
        } catch {
            accessibilityFailure = .unsupportedApplication
        }

        try Task.checkCancellation()
        do {
            return try await ocr.extract(at: point, displayID: displayID)
        } catch is CancellationError {
            throw CancellationError()
        } catch let ocrFailure as ExtractionError {
            if accessibilityFailure == .accessibilityPermissionRequired {
                throw accessibilityFailure
            }
            if ocrFailure == .screenCapturePermissionRequired {
                throw ocrFailure
            }
            if accessibilityFailure == .noTextAtPointer && ocrFailure == .noTextAtPointer {
                throw ExtractionError.noTextAtPointer
            }
            throw ocrFailure
        }
    }
}
