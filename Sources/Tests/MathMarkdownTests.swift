import XCTest
import AppKit
@testable import mrkd

/// Math end to end through `MarkdownRenderer`: real cmark, real smart
/// typography, real SwaTex layout. The assertions are on the finished
/// attributed string, which is what the text view is handed.
final class MathMarkdownTests: XCTestCase {

    private func render(_ markdown: String) -> NSAttributedString {
        MarkdownRenderer.render(markdown)
    }

    private func deferred(in text: NSAttributedString) -> [DeferredAttachment] {
        DeferredAttachment.all(in: text).map(\.attachment)
    }

    private func attachment(in text: NSAttributedString, at range: NSRange) -> NSTextAttachment? {
        text.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
    }

    // MARK: - Recognised

    func testInlineMathBecomesADeferredAttachmentCarryingItsLatex() {
        let result = render("Einstein wrote $E = mc^2$ on a board.")
        XCTAssertEqual(
            deferred(in: result),
            [DeferredAttachment(kind: .inlineMath, source: "E = mc^2")]
        )
        XCTAssertFalse(result.string.contains("$"), "the delimiters must not survive")
        XCTAssertTrue(result.string.contains("Einstein wrote "))
        XCTAssertTrue(result.string.contains(" on a board."))
    }

    func testDisplayMathBecomesADeferredAttachment() {
        let result = render("Before.\n\n$$\n\\int_0^1 x\\,dx\n$$\n\nAfter.")
        XCTAssertEqual(
            deferred(in: result),
            [DeferredAttachment(kind: .displayMath, source: "\\int_0^1 x\\,dx")]
        )
    }

    func testMathAttachmentIsSizedAndSitsOnTheTextBaseline() throws {
        let result = render("A subscript $x_1$ here.")
        let entry = try XCTUnwrap(DeferredAttachment.all(in: result).first)
        let attachment = try XCTUnwrap(self.attachment(in: result, at: entry.range))
        XCTAssertGreaterThan(attachment.bounds.width, 0, "a zero-width box would collapse the line")
        XCTAssertGreaterThan(attachment.bounds.height, 0)
        XCTAssertLessThan(attachment.bounds.origin.y, 0, "the subscript hangs below the baseline")
    }

    /// cmark would eat the backslashes and read `_` as emphasis; smart
    /// typography would curl the prime into a right single quote. The
    /// formula is lifted out before either of them runs, so it arrives
    /// exactly as it was written.
    func testFormulaSurvivesSmartTypographyAndCmarkIntact() {
        let result = render("The derivative $f'(x) = 2x$ and $a \\\\ b$ hold.")
        XCTAssertEqual(
            deferred(in: result).map(\.source),
            ["f'(x) = 2x", "a \\\\ b"]
        )
    }

    func testMathIsTaggedWithItsSourceBlock() throws {
        let result = render("# Title\n\nA formula $x^2$ here.")
        let entry = try XCTUnwrap(DeferredAttachment.all(in: result).first)
        let index = result.attribute(.sourceBlockIndex, at: entry.range.location, effectiveRange: nil) as? Int
        XCTAssertEqual(index, 1, "the formula is in the second block, and the accent needs to know")
    }

    func testDisplayMathIsCentredOnItsOwnLine() throws {
        let result = render("Before.\n\n$$x + y$$\n\nAfter.")
        let entry = try XCTUnwrap(DeferredAttachment.all(in: result).first)
        let style = result.attribute(.paragraphStyle, at: entry.range.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.alignment, .center)
    }

    func testInlineMathIsNotCentred() throws {
        let result = render("Some prose with $x + y$ inside it.")
        let entry = try XCTUnwrap(DeferredAttachment.all(in: result).first)
        let style = result.attribute(.paragraphStyle, at: entry.range.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotEqual(style?.alignment, .center)
    }

    /// Alone on its line, an inline formula is still an inline formula:
    /// the author wrote single dollars, so it stays where the text would be.
    func testInlineMathAloneOnALineIsStillNotCentred() throws {
        let result = render("Before.\n\n$x + y$\n\nAfter.")
        let entry = try XCTUnwrap(DeferredAttachment.all(in: result).first)
        let style = result.attribute(.paragraphStyle, at: entry.range.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotEqual(style?.alignment, .center)
    }

    /// Display delimiters used mid-sentence still render the formula, but
    /// centring the paragraph would drag the prose into the middle too.
    func testDisplayMathInsideASentenceDoesNotCentreTheProse() throws {
        let result = render("Prose about $$x + y$$ continuing here.")
        let entry = try XCTUnwrap(DeferredAttachment.all(in: result).first)
        let style = result.attribute(.paragraphStyle, at: entry.range.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotEqual(style?.alignment, .center)
    }

    // MARK: - Left alone

    func testCurrencyIsRenderedAsText() {
        let result = render("It cost $5 and then $10 more.")
        XCTAssertEqual(deferred(in: result), [])
        XCTAssertTrue(result.string.contains("$5"))
        XCTAssertTrue(result.string.contains("$10"))
    }

    func testMathInsideACodeSpanIsRenderedAsCode() {
        let result = render("Write `$x$` to get math.")
        XCTAssertEqual(deferred(in: result), [])
        XCTAssertTrue(result.string.contains("$x$"))
    }

    func testMathInsideAFencedCodeBlockIsRenderedAsCode() {
        let result = render("```sh\necho $$ > pid\n$x$\n```")
        XCTAssertEqual(deferred(in: result), [])
        XCTAssertTrue(result.string.contains("$$"))
        XCTAssertTrue(result.string.contains("$x$"))
    }

    func testFormulaSwaTexCannotParseFallsBackToItsSource() {
        let result = render("Broken $\\frac{1}{$ formula.")
        XCTAssertEqual(deferred(in: result), [], "no attachment for something that cannot render")
        XCTAssertTrue(
            result.string.contains("$\\frac{1}{$"),
            "the author must see what they wrote, not a gap — got \(result.string)"
        )
    }

    func testNoPlaceholderCharactersLeakIntoTheDocument() {
        let result = render("Mix $x$ with $5 and `$y$` and $$z$$.")
        XCTAssertFalse(result.string.contains("\u{E000}"))
        XCTAssertFalse(result.string.contains("\u{E001}"))
    }

    // MARK: - The seam images already ride

    func testImagesStillResolveThroughTheDeferredSeam() {
        let result = render("![alt](diagram.png)")
        XCTAssertEqual(
            deferred(in: result),
            [DeferredAttachment(kind: .image, source: "diagram.png")]
        )
    }

    func testProgressiveRenderAlsoSubstitutesMath() {
        var firstScreen: NSAttributedString?
        let full = MarkdownRenderer.renderProgressive(
            "A formula $x^2$ here.",
            firstScreenBlocks: 1,
            onFirstScreen: { firstScreen = $0 }
        )
        XCTAssertEqual(
            deferred(in: try! XCTUnwrap(firstScreen)),
            [DeferredAttachment(kind: .inlineMath, source: "x^2")]
        )
        XCTAssertEqual(
            deferred(in: full),
            [DeferredAttachment(kind: .inlineMath, source: "x^2")]
        )
    }
}
