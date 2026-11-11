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

    // applyContextualSpacing gets its start position from the attributed
    // string's length, which counts UTF-16 code units. It used to step
    // through the Swift String by Characters instead. An emoji is one
    // Character but several UTF-16 units, so every emoji before a block
    // pushed the two counts further apart.

    private func spacingBefore(in result: NSAttributedString, at location: Int) -> CGFloat {
        let style = result.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        return style?.paragraphSpacingBefore ?? 0
    }

    func testRenderDoesNotCrashWhenEmojiOutnumberTheRestOfTheDocument() {
        // Each family emoji is 11 UTF-16 units but one Character. Three of
        // them put the start position past the end of the string counted in
        // Characters, which trapped with "String index is out of bounds".
        let markdown = String(repeating: "👨‍👩‍👧‍👦", count: 3) + "\n\nend"
        let result = MarkdownRenderer.render(markdown)
        let end = (result.string as NSString).range(of: "end")
        XCTAssertNotEqual(end.location, NSNotFound)
        XCTAssertGreaterThan(spacingBefore(in: result, at: end.location), 0)
        XCTAssertGreaterThan(spacingBefore(in: result, at: NSMaxRange(end) - 1), 0)
    }

    func testContextualSpacingCoversTheWholeParagraphAfterAnEmoji() {
        // One emoji is not enough to crash, but the spacing range came out
        // one unit short and missed the paragraph's last character.
        let result = MarkdownRenderer.render("👍 one\n\ntwo three")
        let text = result.string as NSString
        let two = text.range(of: "two")
        let three = text.range(of: "three")
        XCTAssertGreaterThan(spacingBefore(in: result, at: two.location), 0)
        XCTAssertGreaterThan(
            spacingBefore(in: result, at: NSMaxRange(three) - 1), 0,
            "the last character of the second paragraph must carry its spacing"
        )
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

    // MARK: - Front matter

    private func headingTexts(in result: NSAttributedString) -> [String] {
        var texts: [String] = []
        let text = result.string as NSString
        result.enumerateAttribute(
            .accessibilityHeadingLevel,
            in: NSRange(location: 0, length: result.length)
        ) { value, range, _ in
            if value != nil { texts.append(text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return texts
    }

    /// Without this, CommonMark reads the opening `---` as a rule and the
    /// YAML lines plus the closing `---` as a level-2 heading.
    func testFrontMatterRendersAsACodeBlockAndNotAsAHeading() {
        let source = "---\ntitle: My plan\nstatus: draft\n---\n\n# Real heading\n\nBody."
        let result = MarkdownRenderer.render(source)
        let text = result.string as NSString

        XCTAssertEqual(headingTexts(in: result), ["Real heading"])

        let title = text.range(of: "title: My plan")
        XCTAssertNotEqual(title.location, NSNotFound, "the front matter must still be shown")
        let style = result.attribute(.paragraphStyle, at: title.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertFalse(style?.textBlocks.isEmpty ?? true, "front matter must sit in a code block")
        XCTAssertFalse(result.string.contains("---"), "the delimiters are not part of the content")
    }

    func testTheBlockAfterFrontMatterKeepsItsSourceIndex() {
        // Block 0 is the front matter, so the heading is block 1. The
        // changed-block highlight depends on the two counts agreeing.
        let result = MarkdownRenderer.render("---\na: 1\n\nb: 2\n---\n\n# Heading")
        let heading = (result.string as NSString).range(of: "Heading")
        XCTAssertEqual(result.attribute(.sourceBlockIndex, at: heading.location, effectiveRange: nil) as? Int, 1)
    }

    /// The text blocks that draw a horizontal rule: a line along the bottom
    /// edge, as wide as the column.
    private func ruleBlocks(in result: NSAttributedString) -> [NSTextBlock] {
        var blocks: [NSTextBlock] = []
        result.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            for block in (value as? NSParagraphStyle)?.textBlocks ?? []
            where block.width(for: .border, edge: .maxY) > 0 && !blocks.contains(where: { $0 === block }) {
                blocks.append(block)
            }
        }
        return blocks
    }

    func testAHyphenRuleRendersAsARuleAndNotAsADash() {
        let result = MarkdownRenderer.render("Above\n\n---\n\nBelow")
        XCTAssertFalse(result.string.contains("\u{2014}"), "got: \(result.string.debugDescription)")
        XCTAssertEqual(ruleBlocks(in: result).count, 1, "the rule must be drawn like `***` is")
    }

    /// A rule is a line across the column at any width, never a run of
    /// characters that wraps when the column is narrow.
    func testARuleIsALineAsWideAsTheColumn() {
        let theme = DefaultTheme()
        for source in ["Above\n\n***\n\nBelow", "Above\n\n___\n\nBelow", "Above\n\n- - -\n\nBelow"] {
            let result = MarkdownRenderer.render(source, theme: theme)
            XCTAssertFalse(result.string.contains("\u{2500}"), "no drawn characters: \(source)")
            guard let rule = ruleBlocks(in: result).first else { return XCTFail("no rule in \(source)") }
            XCTAssertEqual(rule.value(for: .width), 100, source)
            XCTAssertEqual(rule.valueType(for: .width), .percentageValueType, source)
            XCTAssertEqual(rule.borderColor(for: .maxY), theme.tableBorderColor, source)
            XCTAssertEqual(rule.width(for: .border, edge: .minY), 0, "one line, not a box: \(source)")
        }
    }

    func testARuleLaterInTheDocumentIsNotFrontMatter() {
        let result = MarkdownRenderer.render("Intro\n\n---\n\nSection\n---")
        XCTAssertEqual(headingTexts(in: result), ["Section"])
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
