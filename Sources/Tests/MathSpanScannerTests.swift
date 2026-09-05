import XCTest
@testable import mrkd

/// The scanner is where the false-positive risk lives. `$5 and $10` is
/// money, `$HOME/$USER` is a shell variable, `` `$x$` `` is code, and a
/// `$$` inside a fence is a process ID. Every one of those must survive
/// unchanged; only real formulas may be lifted out.
final class MathSpanScannerTests: XCTestCase {

    private func extract(
        _ block: String,
        firstIndex: Int = 0
    ) -> (source: String, spans: [MathSpan]) {
        MathSpanScanner.extract(from: block, firstIndex: firstIndex)
    }

    // MARK: - What must be recognised

    func testInlineMathIsLiftedOutAndReplacedByAPlaceholder() {
        let (source, spans) = extract("Einstein wrote $E = mc^2$ on a board.")
        XCTAssertEqual(spans, [MathSpan(latex: "E = mc^2", isDisplay: false)])
        XCTAssertEqual(source, "Einstein wrote \(MathSpanScanner.placeholder(0)) on a board.")
    }

    func testDisplayMathSpansLinesAndIsTrimmed() {
        let (source, spans) = extract("$$\n\\int_0^1 x\\,dx\n$$")
        XCTAssertEqual(spans, [MathSpan(latex: "\\int_0^1 x\\,dx", isDisplay: true)])
        XCTAssertEqual(source, MathSpanScanner.placeholder(0))
    }

    func testDisplayMathOnASingleLine() {
        let (_, spans) = extract("$$a + b$$")
        XCTAssertEqual(spans, [MathSpan(latex: "a + b", isDisplay: true)])
    }

    func testDisplayIsPreferredOverTwoInlineSpans() {
        let (_, spans) = extract("$$x$$")
        XCTAssertEqual(spans.map(\.isDisplay), [true], "$$x$$ is one display formula, not inline")
    }

    func testSeveralSpansInOneBlockAreNumberedInOrder() {
        let (source, spans) = extract("First $a$ then $b$.")
        XCTAssertEqual(spans, [
            MathSpan(latex: "a", isDisplay: false),
            MathSpan(latex: "b", isDisplay: false),
        ])
        XCTAssertEqual(
            source,
            "First \(MathSpanScanner.placeholder(0)) then \(MathSpanScanner.placeholder(1))."
        )
    }

    func testPlaceholderNumberingContinuesFromTheGivenIndex() {
        let (source, spans) = extract("Then $c$.", firstIndex: 3)
        XCTAssertEqual(spans, [MathSpan(latex: "c", isDisplay: false)])
        XCTAssertEqual(source, "Then \(MathSpanScanner.placeholder(3)).")
    }

    // MARK: - What must be left alone

    func testCurrencyIsNotMath() {
        let block = "It cost $5 and then $10 more."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [], "a closing $ preceded by a space is not a delimiter")
        XCTAssertEqual(source, block)
    }

    func testShellVariablesAreNotMath() {
        let block = "Set $HOME/$USER before running."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [], "a closing $ followed by a letter is not a delimiter")
        XCTAssertEqual(source, block)
    }

    func testCodeSpanIsNotMath() {
        let block = "Write `$x$` to get math."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    func testMultiBacktickCodeSpanIsNotMath() {
        let block = "Write ``$x$ and `y`$`` to get math."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    func testFencedCodeIsNotMath() {
        let block = "```sh\necho $$ > pid\n$x$\n```"
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    func testTildeFencedCodeIsNotMath() {
        let block = "~~~\n$x$\n~~~"
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    func testProseAfterAClosedFenceIsStillScanned() {
        let (source, spans) = extract("```\n$a$\n```\nand $b$ after.")
        XCTAssertEqual(spans, [MathSpan(latex: "b", isDisplay: false)],
                       "only the formula outside the fence is math")
        XCTAssertEqual(source, "```\n$a$\n```\nand \(MathSpanScanner.placeholder(0)) after.")
    }

    /// Display math is consumed in one jump, and the lines it swallowed
    /// still have to count — otherwise everything after it is measured
    /// against the wrong line and a fence stops protecting its contents.
    /// A tilde fence, so that the backtick tracking cannot mask a wrong
    /// line count: the fence map is the only thing protecting `$b$` here.
    func testLinesConsumedByDisplayMathStillCountTowardTheFenceMap() {
        let (source, spans) = extract("$$\na\n$$\n~~~\n$b$\n~~~")
        XCTAssertEqual(spans, [MathSpan(latex: "a", isDisplay: true)])
        XCTAssertEqual(source, "\(MathSpanScanner.placeholder(0))\n~~~\n$b$\n~~~")
    }

    func testIndentedCodeBlockIsNotMath() {
        let block = "    let price = $5\n    let other = $10$"
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    /// An escaped dollar is not a delimiter at all — including as an
    /// *opener*, which is what stops the escaped prices here from opening a
    /// formula that then runs on until the real one closes it.
    func testEscapedDollarsAreNotDelimiters() {
        let block = "Costs \\$5 and \\$10, but $x$ is math."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [MathSpan(latex: "x", isDisplay: false)])
        XCTAssertEqual(source, "Costs \\$5 and \\$10, but \(MathSpanScanner.placeholder(0)) is math.")
    }

    func testOpeningDollarFollowedByASpaceIsNotMath() {
        let block = "Pay $ x$ please."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [], "a padded opener is a currency sign, not a delimiter")
        XCTAssertEqual(source, block)
    }

    func testUnclosedDollarIsLeftAlone() {
        let block = "The price is $42 today."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    /// The second line closes with a `$` that passes every other test, so
    /// only the line rule stops one bullet's stray dollar from swallowing
    /// the next bullet whole.
    func testInlineMathDoesNotCrossALineBreak() {
        let block = "- Coffee is $3\n- Tea costs 2$ or so"
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [], "an unterminated $ must not swallow the next line")
        XCTAssertEqual(source, block)
    }

    /// `$$x$` closes only once. The first `$` cannot open inline math —
    /// otherwise the formula would come out as `$x` with a stray delimiter
    /// baked into it — so it is emitted literally and the scan picks the
    /// real formula up from the second one.
    func testDisplayOpenerNeverStartsInlineMath() {
        let (source, spans) = extract("$$x$")
        XCTAssertEqual(spans, [MathSpan(latex: "x", isDisplay: false)])
        XCTAssertEqual(source, "$\(MathSpanScanner.placeholder(0))")
    }

    func testUnclosedDisplayMathIsLeftAlone() {
        let block = "$$\nx = 1\nno closing fence"
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    func testEmptyDisplayDelimitersAreNotMath() {
        let block = "An empty $$$$ formula."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    func testALoneDisplayMarkerIsNotMath() {
        let block = "A lone $$ marker."
        let (source, spans) = extract(block)
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, block)
    }

    /// Unlike the inline form, `$$` may be padded — `$$ x $$` is ordinary
    /// LaTeX, so the opener rule that protects currency does not apply here.
    func testDisplayMathMayBePaddedWithSpaces() {
        let (_, spans) = extract("$$ x + y $$")
        XCTAssertEqual(spans, [MathSpan(latex: "x + y", isDisplay: true)])
    }

    // MARK: - Placeholder hygiene

    func testPrivateUseCharactersInTheSourceAreDropped() {
        let (source, spans) = extract("before \u{E000}0\u{E001} after")
        XCTAssertEqual(spans, [])
        XCTAssertEqual(source, "before 0 after",
                       "a document cannot be allowed to forge a placeholder")
    }

    func testPlaceholderRangesDecodeBackToTheirIndices() {
        let (source, _) = extract("$a$ and $b$")
        let found = MathSpanScanner.placeholderRanges(in: source as NSString)
        XCTAssertEqual(found.map(\.index), [0, 1])
        let text = source as NSString
        XCTAssertEqual(text.substring(with: found[0].range), MathSpanScanner.placeholder(0))
        XCTAssertEqual(text.substring(with: found[1].range), MathSpanScanner.placeholder(1))
    }

    func testPlaceholderRangesAreEmptyForOrdinaryText() {
        XCTAssertTrue(MathSpanScanner.placeholderRanges(in: "no math here" as NSString).isEmpty)
    }

    // MARK: - Literal fallback text

    func testLiteralRebuildsTheSourceDelimiters() {
        XCTAssertEqual(MathSpan(latex: "x", isDisplay: false).literal, "$x$")
        XCTAssertEqual(MathSpan(latex: "x", isDisplay: true).literal, "$$x$$")
    }
}
