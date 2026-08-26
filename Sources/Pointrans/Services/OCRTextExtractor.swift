import CoreGraphics
import Foundation
import ScreenCaptureKit
@preconcurrency import Vision

actor OCRTextExtractor: TextExtracting {
    struct Configuration: Sendable {
        var captureSize = CGSize(width: 520, height: 120)
        var minimumConfidence: Float = 0.35
        var maximumHorizontalDistance: CGFloat = 70
    }

    enum OCRError: Error, Sendable {
        case permissionDenied
        case captureFailed
        case noCandidate
    }

    private let configuration: Configuration

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    func extract(
        at point: CGPoint,
        displayID: CGDirectDisplayID,
        direction: TranslationDirection
    ) async throws -> ExtractionResult {
        guard CGPreflightScreenCaptureAccess() else { throw OCRError.permissionDenied }
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
            throw OCRError.captureFailed
        }

        let image = try await SCScreenshotManager.captureImage(in: captureRect)
        try Task.checkCancellation()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = direction == .chineseToEnglish ? ["zh-Hans", "en-US"] : ["en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        struct RecognizedLine {
            let text: String
            let bounds: CGRect
        }
        struct TokenCandidate {
            let word: String
            let bounds: CGRect
            let confidence: Float
            let lineBounds: CGRect
        }

        var lines: [RecognizedLine] = []
        var best: TokenCandidate?
        var bestScore = CGFloat.infinity
        for observation in request.results ?? [] {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= configuration.minimumConfidence else { continue }

            let lineBounds = quartzBounds(observation.boundingBox, in: captureRect)
            lines.append(RecognizedLine(text: candidate.string, bounds: lineBounds))
            let padded = lineBounds.insetBy(dx: -4, dy: -8)
            guard padded.minY <= point.y, padded.maxY >= point.y else { continue }

            for token in TextTokenizer.tokenize(candidate.string, direction: direction) {
                guard let tokenObservation = try? candidate.boundingBox(for: token.range) else { continue }
                let bounds = quartzBounds(tokenObservation.boundingBox, in: captureRect)
                let horizontalDistance = abs(bounds.midX - point.x)
                guard horizontalDistance <= configuration.maximumHorizontalDistance else { continue }
                let verticalDistance = abs(bounds.midY - point.y)
                let score = horizontalDistance + verticalDistance * 1.8 + CGFloat(1 - candidate.confidence) * 40
                if score < bestScore {
                    bestScore = score
                    best = TokenCandidate(
                        word: token.text,
                        bounds: bounds,
                        confidence: candidate.confidence,
                        lineBounds: lineBounds
                    )
                }
            }
        }

        guard let best else { throw OCRError.noCandidate }
        let context = lines
            .filter { abs($0.bounds.midY - best.lineBounds.midY) <= configuration.captureSize.height / 2 }
            .sorted {
                if abs($0.bounds.midY - $1.bounds.midY) > 4 { return $0.bounds.midY < $1.bounds.midY }
                return $0.bounds.minX < $1.bounds.minX
            }
            .map(\.text)
            .joined(separator: " ")

        return ExtractionResult(
            word: best.word,
            context: TextTokenizer.truncatedUTF16(context, maximumLength: 600),
            bounds: best.bounds,
            confidence: best.confidence,
            source: .ocr
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
