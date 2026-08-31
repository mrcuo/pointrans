import CoreGraphics
import Foundation
import ScreenCaptureKit
@preconcurrency import Vision

actor OCRTextExtractor: TextExtracting {
    struct Configuration: Sendable {
        var captureSize = CGSize(width: 520, height: 120)
        var minimumConfidence: Float = 0.35
        var tokenHitPadding = CGSize(width: 5, height: 7)
    }

    private let configuration: Configuration

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    func extract(
        at point: CGPoint,
        displayID: CGDirectDisplayID
    ) async throws -> ExtractionResult {
        guard CGPreflightScreenCaptureAccess() else { throw ExtractionError.screenCapturePermissionRequired }
        try Task.checkCancellation()

        let displayBounds = CGDisplayBounds(displayID)
        let desired = CGRect(
            x: point.x - configuration.captureSize.width / 2,
            y: point.y - configuration.captureSize.height / 2,
            width: configuration.captureSize.width,
            height: configuration.captureSize.height
        )
        let captureRect = desired.intersection(displayBounds)
        guard !captureRect.isNull, captureRect.width > 20, captureRect.height > 20 else {
            throw ExtractionError.captureFailed
        }

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(in: captureRect)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ExtractionError.captureFailed
        }
        try Task.checkCancellation()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        struct TokenCandidate {
            let word: String
            let bounds: CGRect
            let confidence: Float
            let lineText: String
            let tokenRange: Range<String.Index>
        }

        var best: TokenCandidate?
        var bestScore = CGFloat.infinity
        for observation in request.results ?? [] {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= configuration.minimumConfidence else { continue }

            let lineBounds = quartzBounds(observation.boundingBox, in: captureRect)
            let padded = lineBounds.insetBy(dx: -4, dy: -8)
            guard padded.minY <= point.y, padded.maxY >= point.y else { continue }

            for token in TextTokenizer.tokenize(candidate.string) {
                guard let tokenObservation = try? candidate.boundingBox(for: token.range) else { continue }
                let bounds = quartzBounds(tokenObservation.boundingBox, in: captureRect)
                let hitBounds = bounds.insetBy(
                    dx: -configuration.tokenHitPadding.width,
                    dy: -configuration.tokenHitPadding.height
                )
                guard hitBounds.contains(point) else { continue }
                let horizontalDistance = abs(bounds.midX - point.x)
                let verticalDistance = abs(bounds.midY - point.y)
                let score = horizontalDistance + verticalDistance * 1.8 + CGFloat(1 - candidate.confidence) * 40
                if score < bestScore {
                    bestScore = score
                    best = TokenCandidate(
                        word: token.text,
                        bounds: bounds,
                        confidence: candidate.confidence,
                        lineText: candidate.string,
                        tokenRange: token.range
                    )
                }
            }
        }

        guard let best else { throw ExtractionError.noTextAtPointer }
        let contextWindow = TextTokenizer.contextWindow(around: best.tokenRange, in: best.lineText)

        return ExtractionResult(
            word: best.word,
            context: contextWindow?.text ?? best.word,
            targetUTF16Range: contextWindow?.targetUTF16Range ?? NSRange(location: 0, length: best.word.utf16.count),
            bounds: best.bounds,
            confidence: best.confidence,
            source: .ocr,
            detectedLanguage: .detect(best.word)
        )
    }

    private func quartzBounds(_ normalized: CGRect, in captureRect: CGRect) -> CGRect {
        CGRect(
            x: captureRect.minX + normalized.minX * captureRect.width,
            y: captureRect.maxY - normalized.maxY * captureRect.height,
            width: normalized.width * captureRect.width,
            height: normalized.height * captureRect.height
        )
    }
}
