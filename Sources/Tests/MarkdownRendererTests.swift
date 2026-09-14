import XCTest
import AppKit
@testable import mrkd

final class MarkdownRendererTests: XCTestCase {

    func testRenderPlainParagraphProducesText() {
        let result = MarkdownRenderer.render("Hello world.")
        XCTAssertTrue(result.string.contains("Hello world."))
    }

    func testRenderHeadingStampsAccessibilityLevel() {
        let result = MarkdownRenderer.render("# Title\n\nbody")
        var found: Int?
        let full = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.accessibilityHeadingLevel, in: full) { value, _, stop in
            if let level = value as? Int {
                found = level
                stop.pointee = true
            }
        }
        XCTAssertEqual(found, 1, "h1 must stamp .accessibilityHeadingLevel = 1")
    }

    func testRenderH2StampsLevel2() {
        let result = MarkdownRenderer.render("## Section")
        var found: Int?
        result.enumerateAttribute(
            .accessibilityHeadingLevel,
            in: NSRange(location: 0, length: result.length)
        ) { value, _, stop in
            if let level = value as? Int { found = level; stop.pointee = true }
        }
        XCTAssertEqual(found, 2)
    }

    func testSmartTypographyIsAppliedToProse() {
        // Default theme allows smart typography (smartTypographyAllowed = true).
        let result = MarkdownRenderer.render(#"It's "great" today."#)
        XCTAssertTrue(result.string.contains("\u{2019}"), "apostrophe must curl")
        XCTAssertTrue(result.string.contains("\u{201C}great\u{201D}"), "double quotes must curl")
    }

    func testRenderDoesNotCrashWhenEmojiPrecedesLaterBlock() {
        // Regression test: applyContextualSpacing indexed the attributed
        // string's UTF-16 length into a Swift String by Character offset.
        // An emoji (two UTF-16 code units, one Character) before a later
        // block made the offset exceed the character count and trap with
        // "String index is out of bounds".
        let markdown = "👍 note\n\nparagraph two"
        let result = MarkdownRenderer.render(markdown)
        XCTAssertTrue(result.string.contains("paragraph two"))

        // The later paragraph must still receive its contextual spacing.
        var spacingApplied = false
        result.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: result.length)
        ) { value, _, _ in
            if let style = value as? NSParagraphStyle,
               style.paragraphSpacingBefore > 0 {
                spacingApplied = true
            }
        }
        XCTAssertTrue(spacingApplied, "second paragraph must get spacingBefore")
    }

    func testRenderSurvivesEmojiInsideLongerDocument() {
        // Wider regression sweep: emoji in headings, lists, code fences and
        // blockquotes, all followed by blocks that need contextual spacing.
        // Separator string keeps the raw literal from collapsing leading
        // whitespace per line.
        let markdown = #"""
        # 🏔️ 山

        - 条目 📌
        - 再一条

        > 引用 🐱

        ```swift
        let x = 1 // 🌈
        ```

        | A | B |
        |---|--|
        | ✨ | ✅ |

        ## 结尾段落
        """#
        let result = MarkdownRenderer.render(markdown)
        XCTAssertTrue(result.string.contains("结尾段落"))
    }

    func testSmartTypographySkippedWhenThemeOptsOut() {
        struct NoSmart: Theme {
            let name = "NoSmart"
            let baseFontSize: CGFloat = 13
            let fontFamily = "SF Mono"
            let codeFontFamily = "SF Mono"
            var backgroundColor: NSColor { .windowBackgroundColor }
            var textColor: NSColor { .labelColor }
            var linkColor: NSColor { .linkColor }
            var codeBackgroundColor: NSColor { .controlBackgroundColor }
            var codeTextColor: NSColor { .labelColor }
            var blockquoteColor: NSColor { .secondaryLabelColor }
            var blockquoteBarColor: NSColor { .tertiaryLabelColor }
            var smartTypographyAllowed: Bool { false }
            func headingColor(level: Int) -> NSColor { .labelColor }
        }
        let result = MarkdownRenderer.render(#"It's "great"."#, theme: NoSmart())
        XCTAssertTrue(result.string.contains("It's"), "apostrophe must remain straight")
        XCTAssertTrue(result.string.contains(#""great""#), "quotes must remain straight")
    }

    func testFencedCodeBlockLeadingNewlineIsStripped() {
        // Source has a literal blank line right after the opening fence —
        // cmark preserves the leading \n in the literal. Renderer should strip.
        let source = "```\n\ncode\n```"
        let result = MarkdownRenderer.render(source)
        // The rendered string shouldn't start the code content with a newline.
        // We detect this by checking that no two consecutive newlines occur
        // right before "code".
        XCTAssertFalse(result.string.contains("\n\ncode"),
            "leading newline inside fenced block should not produce a blank line")
    }
}
