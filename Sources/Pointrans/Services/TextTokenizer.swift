import Foundation

enum TextTokenizer {
    struct Token: Equatable, Sendable {
        let text: String
        let range: Range<String.Index>
    }

    static func token(
        atUTF16Offset offset: Int,
        in text: String,
        direction: TranslationDirection,
        maximumNearestUTF16Distance: Int = 2
    ) -> Token? {
        guard !text.isEmpty else { return nil }
        let utf16 = text.utf16
        let safeOffset = min(max(offset, 0), max(utf16.count - 1, 0))
        guard let utf16Index = utf16.index(utf16.startIndex, offsetBy: safeOffset, limitedBy: utf16.endIndex),
              let index = String.Index(utf16Index, within: text) else { return nil }

        let tokens = tokenize(text, direction: direction)
        if let direct = tokens.first(where: { $0.range.contains(index) }) { return direct }

        guard let nearest = tokens.min(by: {
            utf16Distance(from: safeOffset, to: $0.range, in: text) <
                utf16Distance(from: safeOffset, to: $1.range, in: text)
        }), utf16Distance(from: safeOffset, to: nearest.range, in: text) <= maximumNearestUTF16Distance else {
            return nil
        }
        return nearest
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
        let paragraph = text.rangeOfParagraph(containing: range.lowerBound)
        let value = String(text[paragraph])
        guard value.utf16.count > maximumUTF16Length else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let paragraphLocation = NSRange(text.startIndex..<paragraph.lowerBound, in: text).length
        let tokenLocation = NSRange(text.startIndex..<range.lowerBound, in: text).length - paragraphLocation
        let centeredStart = tokenLocation - maximumUTF16Length / 2
        let start = min(max(centeredStart, 0), value.utf16.count - maximumUTF16Length)
        let units = Array(value.utf16)
        let window = String(decoding: units[start..<(start + maximumUTF16Length)], as: UTF16.self)
        return window.trimmingCharacters(in: .whitespacesAndNewlines)
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
