import Foundation

enum TextTokenizer {
    struct Token: Equatable, Sendable {
        let text: String
        let range: Range<String.Index>
    }

    struct ContextWindow: Equatable, Sendable {
        let text: String
        let targetUTF16Range: NSRange
    }

    static func token(
        atUTF16Offset offset: Int,
        in text: String,
        maximumNearestUTF16Distance: Int = 2
    ) -> Token? {
        guard !text.isEmpty else { return nil }
        let utf16 = text.utf16
        let safeOffset = min(max(offset, 0), max(utf16.count - 1, 0))
        guard let utf16Index = utf16.index(utf16.startIndex, offsetBy: safeOffset, limitedBy: utf16.endIndex),
              let index = String.Index(utf16Index, within: text) else { return nil }

        let tokens = tokenize(text)
        if let direct = tokens.first(where: { $0.range.contains(index) }) { return direct }

        guard let nearest = tokens.min(by: {
            utf16Distance(from: safeOffset, to: $0.range, in: text) <
                utf16Distance(from: safeOffset, to: $1.range, in: text)
        }), utf16Distance(from: safeOffset, to: nearest.range, in: text) <= maximumNearestUTF16Distance else {
            return nil
        }
        return nearest
    }

    static func token(
        atUTF16Offset offset: Int,
        in text: String,
        direction: TranslationDirection,
        maximumNearestUTF16Distance: Int = 2
    ) -> Token? {
        token(
            atUTF16Offset: offset,
            in: text,
            maximumNearestUTF16Distance: maximumNearestUTF16Distance
        ).flatMap { DetectedLanguage.detect($0.text).direction == direction ? $0 : nil }
    }

    static func tokenize(_ text: String) -> [Token] {
        (englishTokens(in: text) + chineseTokens(in: text)).sorted {
            $0.range.lowerBound < $1.range.lowerBound
        }
    }

    static func tokenize(_ text: String, direction: TranslationDirection) -> [Token] {
        switch direction {
        case .englishToChinese:
            englishTokens(in: text)
        case .chineseToEnglish:
            chineseTokens(in: text)
        }
    }

    static func context(around range: Range<String.Index>, in text: String, maximumUTF16Length: Int = 600) -> String {
        contextWindow(around: range, in: text, maximumUTF16Length: maximumUTF16Length)?.text ?? ""
    }

    static func contextWindow(
        around targetRange: Range<String.Index>,
        in text: String,
        maximumUTF16Length: Int = 600
    ) -> ContextWindow? {
        guard !targetRange.isEmpty else { return nil }
        var selectedRange = text.rangeOfParagraph(containing: targetRange.lowerBound)
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .localized]) {
            _, sentenceRange, _, stop in
            if sentenceRange.overlaps(targetRange) {
                selectedRange = sentenceRange
                stop = true
            }
        }

        let raw = String(text[selectedRange])
        let rawTargetLocation = NSRange(selectedRange.lowerBound..<targetRange.lowerBound, in: text).length
        let rawTargetLength = NSRange(targetRange, in: text).length
        let leadingWhitespace = raw.prefix { $0.isWhitespace }.utf16.count
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let adjustedTarget = NSRange(
            location: max(0, rawTargetLocation - leadingWhitespace),
            length: rawTargetLength
        )
        return boundedContext(trimmed, targetUTF16Range: adjustedTarget, maximumUTF16Length: maximumUTF16Length)
    }

    static func boundedContext(
        _ value: String,
        targetUTF16Range: NSRange?,
        maximumUTF16Length: Int = 600
    ) -> ContextWindow? {
        guard maximumUTF16Length > 0, !value.isEmpty else { return nil }
        let nsValue = value as NSString
        let validTarget: NSRange
        if let targetUTF16Range,
           targetUTF16Range.location >= 0,
           targetUTF16Range.length > 0,
           NSMaxRange(targetUTF16Range) <= nsValue.length {
            validTarget = targetUTF16Range
        } else {
            validTarget = NSRange(location: 0, length: min(nsValue.length, 1))
        }
        guard nsValue.length > maximumUTF16Length else {
            return ContextWindow(text: value, targetUTF16Range: validTarget)
        }

        let centeredStart = validTarget.location + validTarget.length / 2 - maximumUTF16Length / 2
        let start = min(max(centeredStart, 0), nsValue.length - maximumUTF16Length)
        var composedRange = nsValue.rangeOfComposedCharacterSequences(
            for: NSRange(location: start, length: maximumUTF16Length)
        )
        while composedRange.length > maximumUTF16Length {
            let last = nsValue.rangeOfComposedCharacterSequence(at: NSMaxRange(composedRange) - 1)
            composedRange.length = last.location - composedRange.location
        }
        guard NSLocationInRange(validTarget.location, composedRange),
              NSMaxRange(validTarget) <= NSMaxRange(composedRange) else { return nil }
        return ContextWindow(
            text: nsValue.substring(with: composedRange),
            targetUTF16Range: NSRange(
                location: validTarget.location - composedRange.location,
                length: validTarget.length
            )
        )
    }

    static func truncatedUTF16(_ value: String, maximumLength: Int) -> String {
        guard value.utf16.count > maximumLength else { return value }
        guard maximumLength > 0 else { return "" }

        var used = 0
        var end = value.startIndex
        while end < value.endIndex {
            let next = value.index(after: end)
            let width = value[end..<next].utf16.count
            guard used + width <= maximumLength else { break }
            used += width
            end = next
        }
        return String(value[..<end])
    }

    private static func englishTokens(in text: String) -> [Token] {
        let pattern = #"[A-Za-z]+(?:['’-][A-Za-z]+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: full).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return Token(text: String(text[range]), range: range)
        }
    }

    private static func chineseTokens(in text: String) -> [Token] {
        var output: [Token] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) {
            substring, range, _, _ in
            guard let substring, containsHan(substring) else { return }
            output.append(Token(text: substring, range: range))
        }
        if !output.isEmpty { return output }

        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byComposedCharacterSequences) {
            substring, range, _, _ in
            guard let substring, containsHan(substring) else { return }
            output.append(Token(text: substring, range: range))
        }
        return output
    }

    private static func containsHan(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x20000...0x2FA1F).contains(scalar.value)
        }
    }

    private static func utf16Distance(
        from offset: Int,
        to range: Range<String.Index>,
        in text: String
    ) -> Int {
        let tokenRange = NSRange(range, in: text)
        if offset < tokenRange.location { return tokenRange.location - offset }
        if offset >= NSMaxRange(tokenRange) { return offset - NSMaxRange(tokenRange) }
        return 0
    }
}

private extension String {
    func rangeOfParagraph(containing index: Index) -> Range<Index> {
        let separators = CharacterSet.newlines
        var lower = index
        while lower > startIndex {
            let prior = self.index(before: lower)
            guard self[prior].unicodeScalars.allSatisfy({ !separators.contains($0) }) else { break }
            lower = prior
        }

        var upper = index
        while upper < endIndex {
            guard self[upper].unicodeScalars.allSatisfy({ !separators.contains($0) }) else { break }
            upper = self.index(after: upper)
        }
        return lower..<upper
    }
}
