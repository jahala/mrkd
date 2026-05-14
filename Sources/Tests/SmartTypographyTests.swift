import XCTest
@testable import mrkd

final class SmartTypographyTests: XCTestCase {

    // MARK: - Quotes

    func testStraightDoubleQuotesCurl() {
        let result = smartenMarkdown(#"She said "hello" today."#)
        XCTAssertTrue(result.contains("\u{201C}hello\u{201D}"), "got: \(result)")
    }

    func testApostropheCurlsToRightSingleQuote() {
        let result = smartenMarkdown("It's fine.")
        XCTAssertTrue(result.contains("It\u{2019}s"), "got: \(result)")
    }

    // MARK: - Dashes

    func testTripleHyphenBecomesEmDash() {
        let result = smartenMarkdown("He paused---then ran.")
        XCTAssertTrue(result.contains("paused\u{2014}then"), "got: \(result)")
    }

    func testDoubleHyphenBetweenDigitsBecomesEnDash() {
        let result = smartenMarkdown("pages 12--34")
        XCTAssertTrue(result.contains("12\u{2013}34"), "got: \(result)")
    }

    func testDoubleHyphenWithSpacesBecomesEmDash() {
        let result = smartenMarkdown("yes -- no")
        XCTAssertTrue(result.contains("yes \u{2014} no"), "got: \(result)")
    }

    func testCLIFlagDoubleHyphenPreserved() {
        let result = smartenMarkdown("Run --verbose to enable.")
        XCTAssertTrue(result.contains("--verbose"), "CLI flags must survive; got: \(result)")
    }

    // MARK: - Ellipsis

    func testThreeDotsBecomeEllipsis() {
        let result = smartenMarkdown("wait... really?")
        XCTAssertTrue(result.contains("wait\u{2026} really?"), "got: \(result)")
    }

    // MARK: - Skip rules

    func testFencedCodeBlockIsUntouched() {
        let input = "```\nlet x = \"foo\" -- bar\n```"
        XCTAssertEqual(smartenMarkdown(input), input,
            "entire fenced block must round-trip verbatim")
    }

    func testInlineBacktickSpanIsUntouched() {
        let result = smartenMarkdown("Run `--verbose \"value\"` carefully.")
        XCTAssertTrue(result.contains("`--verbose \"value\"`"),
            "inline code must preserve quotes and CLI dashes; got: \(result)")
    }

    func testLinkURLWithParensIsUntouched() {
        let input = "[Wiki](https://en.wikipedia.org/wiki/Foo_(disambig))"
        let result = smartenMarkdown(input)
        XCTAssertTrue(result.contains("https://en.wikipedia.org/wiki/Foo_(disambig)"),
            "URL paren depth must be tracked; got: \(result)")
    }

    func testGFMTableSeparatorRowIsPreserved() {
        let input = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
        let result = smartenMarkdown(input)
        XCTAssertTrue(result.contains("| --- | --- |"),
            "table separator must survive — em-dash conversion would break cmark; got: \(result)")
    }
}
