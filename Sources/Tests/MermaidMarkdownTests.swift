import XCTest
import AppKit
@testable import mrkd

/// Mermaid through `MarkdownRenderer`: real cmark, real fence handling. The
/// assertions are on the finished attributed string, which is what the text
/// view is handed.
final class MermaidMarkdownTests: XCTestCase {

    private func render(_ markdown: String) -> NSAttributedString {
        MarkdownRenderer.render(markdown)
    }

    private func deferred(in text: NSAttributedString) -> [DeferredAttachment] {
        DeferredAttachment.all(in: text).map(\.attachment)
    }

    // MARK: - Recognising the fence

    func testAMermaidFenceBecomesADeferredDiagramCarryingItsSource() {
        let result = render("# Plan\n\n```mermaid\nflowchart TD\n  A --> B\n```\n")

        XCTAssertEqual(
            deferred(in: result),
            [DeferredAttachment(kind: .diagram, source: "flowchart TD\n  A --> B")]
        )
    }

    func testADiagramLeavesNoSourceTextBehindInTheDocument() {
        let result = render("```mermaid\nflowchart TD\n  A --> B\n```\n")

        XCTAssertFalse(
            result.string.contains("flowchart TD"),
            "the source is shown as well as the diagram"
        )
        XCTAssertFalse(result.string.contains("mermaid"), "the language label was left in")
    }

    func testTheFenceLanguageIsMatchedWithoutRegardToCase() {
        XCTAssertEqual(deferred(in: render("```Mermaid\nflowchart TD\n  A --> B\n```")).count, 1)
        XCTAssertEqual(deferred(in: render("```MERMAID\nflowchart TD\n  A --> B\n```")).count, 1)
    }

    func testAMermaidFenceCarriesAPlaceholderImageUntilItIsResolved() throws {
        let result = render("```mermaid\nflowchart TD\n  A --> B\n```")
        let range = try XCTUnwrap(DeferredAttachment.all(in: result).first?.range)
        let attachment = result.attribute(
            .attachment, at: range.location, effectiveRange: nil
        ) as? NSTextAttachment

        // A diagram that has not resolved yet must occupy space, not read as
        // a blank line in the middle of the document.
        let image = try XCTUnwrap(attachment?.image)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// The changed-block accents map rendered text back to source blocks
    /// through this attribute. An attachment that loses it stops being
    /// highlighted when an agent rewrites the diagram.
    func testADiagramAttachmentIsTaggedWithItsSourceBlock() throws {
        let result = render("# Title\n\nA paragraph.\n\n```mermaid\nflowchart TD\n  A --> B\n```\n")
        let range = try XCTUnwrap(DeferredAttachment.all(in: result).first?.range)

        let index = result.attribute(
            .sourceBlockIndex, at: range.location, effectiveRange: nil
        ) as? Int
        XCTAssertEqual(index, 2, "the diagram is the third block in the source")
    }

    // MARK: - Leaving other fences alone

    func testAnOrdinaryCodeFenceIsStillACodeBlock() {
        let result = render("```swift\nlet x = 1\n```\n")

        XCTAssertTrue(deferred(in: result).isEmpty)
        XCTAssertTrue(result.string.contains("let x = 1"))
    }

    func testAFenceThatMerelyStartsWithMermaidIsCode() {
        // ```mermaidjs is not Mermaid, and guessing would hide the source of
        // something this renderer cannot draw.
        let result = render("```mermaidjs\nflowchart TD\n  A --> B\n```\n")

        XCTAssertTrue(deferred(in: result).isEmpty)
        XCTAssertTrue(result.string.contains("flowchart TD"))
    }

    func testAnUnfencedIndentedBlockIsNotADiagram() {
        let result = render("    flowchart TD\n      A --> B\n")

        XCTAssertTrue(deferred(in: result).isEmpty)
        XCTAssertTrue(result.string.contains("flowchart TD"))
    }

    func testIsMermaidFenceAcceptsOnlyTheLanguageItself() {
        XCTAssertTrue(MarkdownRenderer.isMermaidFence("mermaid"))
        XCTAssertTrue(MarkdownRenderer.isMermaidFence("  mermaid  "))
        XCTAssertTrue(MarkdownRenderer.isMermaidFence("MerMaid"))
        XCTAssertFalse(MarkdownRenderer.isMermaidFence("mermaidjs"))
        XCTAssertFalse(MarkdownRenderer.isMermaidFence("mermaid extra"))
        XCTAssertFalse(MarkdownRenderer.isMermaidFence("swift"))
        XCTAssertFalse(MarkdownRenderer.isMermaidFence(""))
        XCTAssertFalse(MarkdownRenderer.isMermaidFence(nil))
    }

    // MARK: - Several diagrams

    func testEveryMermaidBlockInADocumentGetsItsOwnAttachment() {
        let result = render("""
            ```mermaid
            flowchart TD
              A --> B
            ```

            Some prose.

            ```mermaid
            sequenceDiagram
              A->>B: hi
            ```
            """)

        XCTAssertEqual(
            deferred(in: result),
            [
                DeferredAttachment(kind: .diagram, source: "flowchart TD\n  A --> B"),
                DeferredAttachment(kind: .diagram, source: "sequenceDiagram\n  A->>B: hi"),
            ]
        )
    }

    func testDiagramsAndMathShareTheDocumentWithoutDisturbingEachOther() {
        let result = render("""
            Inline $E = mc^2$ here.

            ```mermaid
            flowchart TD
              A --> B
            ```
            """)

        XCTAssertEqual(
            deferred(in: result),
            [
                DeferredAttachment(kind: .inlineMath, source: "E = mc^2"),
                DeferredAttachment(kind: .diagram, source: "flowchart TD\n  A --> B"),
            ]
        )
    }

    // MARK: - The fallback

    func testTheFallbackShowsTheDiagramSourceAsACodeBlock() {
        let source = "flowchart TD\n  A[Unclosed --> B{{{"
        let fallback = MarkdownRenderer.diagramFallback(
            source: source,
            theme: DefaultTheme(),
            sourceBlockIndex: nil
        )

        XCTAssertTrue(
            fallback.string.contains(source),
            "the reader cannot fix a diagram they cannot see"
        )
        XCTAssertTrue(fallback.string.contains("mermaid"), "the language label is missing")
    }

    func testTheFallbackIsStyledLikeACodeBlockRatherThanBareText() {
        let theme = CatppuccinMochaTheme()
        let fallback = MarkdownRenderer.diagramFallback(
            source: "flowchart TD\n  A --> B",
            theme: theme,
            sourceBlockIndex: nil
        )
        let plain = MarkdownRenderer.codeBlock(
            code: "flowchart TD\n  A --> B", language: "mermaid", theme: theme
        )

        XCTAssertEqual(fallback.string, plain.string)
        XCTAssertNotNil(
            fallback.attribute(.paragraphStyle, at: 0, effectiveRange: nil),
            "the fallback has no code-block paragraph style"
        )
    }

    func testTheFallbackKeepsTheSourceBlockTagOfTheDiagramItReplaces() {
        let fallback = MarkdownRenderer.diagramFallback(
            source: "flowchart TD\n  A --> B",
            theme: DefaultTheme(),
            sourceBlockIndex: 7
        )

        for offset in 0..<fallback.length {
            XCTAssertEqual(
                fallback.attribute(.sourceBlockIndex, at: offset, effectiveRange: nil) as? Int,
                7,
                "character \(offset) lost its source-block tag"
            )
        }
    }
}
