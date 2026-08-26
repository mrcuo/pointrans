import XCTest

final class TextTokenizerTests: XCTestCase {
    func testEnglishKeepsApostrophesAndHyphens() {
        let text = "A state-of-the-art tool doesn't guess."
        let tokens = TextTokenizer.tokenize(text, direction: .englishToChinese).map(\.text)
        XCTAssertEqual(tokens, ["A", "state-of-the-art", "tool", "doesn't", "guess"])
    }

    func testPunctuationAndWhitespaceAreNotTokens() {
        let text = "  hello,   world!  "
        XCTAssertEqual(TextTokenizer.tokenize(text, direction: .englishToChinese).map(\.text), ["hello", "world"])
    }

    func testChineseSelectionFindsHanToken() {
        let text = "这个语境非常清楚。"
        let offset = (text as NSString).range(of: "语境").location
        let token = TextTokenizer.token(atUTF16Offset: offset, in: text, direction: .chineseToEnglish)
        XCTAssertNotNil(token)
        XCTAssertTrue(token?.text.contains("语") == true)
    }

    func testLargeWhitespaceDoesNotSelectAnUnrelatedNearbyWord() {
        let text = "hello          world"
        let whitespaceOffset = (text as NSString).range(of: "          ").location + 5
        XCTAssertNil(TextTokenizer.token(
            atUTF16Offset: whitespaceOffset,
            in: text,
            direction: .englishToChinese
        ))
    }

    func testContextWindowStaysBoundedAndKeepsTheTargetWord() throws {
        let prefix = String(repeating: "a", count: 700)
        let target = "target-word"
        let suffix = String(repeating: "b", count: 700)
        let text = prefix + " " + target + " " + suffix
        let targetRange = try XCTUnwrap(text.range(of: target))

        let context = TextTokenizer.context(around: targetRange, in: text, maximumUTF16Length: 600)

        XCTAssertLessThanOrEqual(context.utf16.count, 600)
        XCTAssertTrue(context.contains(target))
    }

    func testUTF16TruncationNeverSplitsAComposedCharacter() {
        let value = "ab👨‍👩‍👧‍👦cd"
        let familyWidth = "👨‍👩‍👧‍👦".utf16.count

        XCTAssertEqual(TextTokenizer.truncatedUTF16(value, maximumLength: 2), "ab")
        XCTAssertEqual(
            TextTokenizer.truncatedUTF16(value, maximumLength: 2 + familyWidth),
            "ab👨‍👩‍👧‍👦"
        )
        XCTAssertFalse(TextTokenizer.truncatedUTF16(value, maximumLength: 3).contains("�"))
    }
}
