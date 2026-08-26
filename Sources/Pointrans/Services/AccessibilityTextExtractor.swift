@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

actor AccessibilityTextExtractor: TextExtracting {
    enum AXExtractionError: Error, Sendable {
        case permissionDenied
        case noElement
        case unsupportedText
        case noToken
    }

    func extract(
        at point: CGPoint,
        displayID: CGDirectDisplayID,
        direction: TranslationDirection
    ) async throws -> ExtractionResult {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw AXExtractionError.permissionDenied }

        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let element = hit else { throw AXExtractionError.noElement }

        let resolved = try resolveText(at: point, startingAt: element)
        let text = resolved.text
        let characterRange = resolved.range
        guard let token = TextTokenizer.token(atUTF16Offset: characterRange.location, in: text, direction: direction) else {
            throw AXExtractionError.noToken
        }

        let tokenRange = NSRange(token.range, in: text)
        let bounds = bounds(for: tokenRange, in: resolved.element) ?? CGRect(origin: point, size: .zero)
        let context = TextTokenizer.context(around: token.range, in: text)
        try Task.checkCancellation()

        return ExtractionResult(
            word: token.text,
            context: context.isEmpty ? token.text : context,
            bounds: bounds,
            confidence: 1,
            source: .accessibility
        )
    }

    private func resolveText(
        at point: CGPoint,
        startingAt hitElement: AXUIElement
    ) throws -> (element: AXUIElement, text: String, range: CFRange) {
        var candidate: AXUIElement? = hitElement

        // Static text is often nested inside AXLink/AXGroup/AXWebArea nodes. Walk
        // a small, deterministic parent chain and use the first element that
        // supports both text and position-to-range mapping.
        for _ in 0..<6 {
            guard let element = candidate else { break }
            if let text = try? textValue(of: element),
               let range = try? range(at: point, in: element),
               range.location >= 0,
               range.location <= text.utf16.count {
                return (element, text, range)
            }
            candidate = parent(of: element)
        }
        throw AXExtractionError.unsupportedText
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &raw) == .success,
              let raw,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private func textValue(of element: AXUIElement) throws -> String {
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success,
           let value = raw as? String, !value.isEmpty {
            return value
        }
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &raw) == .success,
           let title = raw as? String, !title.isEmpty {
            return title
        }
        throw AXExtractionError.unsupportedText
    }

    private func range(at point: CGPoint, in element: AXUIElement) throws -> CFRange {
        var mutablePoint = point
        guard let pointValue = AXValueCreate(.cgPoint, &mutablePoint) else {
            throw AXExtractionError.unsupportedText
        }

        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXRangeForPositionParameterizedAttribute as CFString,
            pointValue,
            &raw
        ) == .success,
        let rangeValue = raw,
        CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            throw AXExtractionError.unsupportedText
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            throw AXExtractionError.unsupportedText
        }
        return range
    }

    private func bounds(for range: NSRange, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &raw
        ) == .success,
        let boundsValue = raw,
        CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }

        var bounds = CGRect.zero
        return AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) ? bounds : nil
    }
}
