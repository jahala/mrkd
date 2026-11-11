import XCTest
import AppKit
@testable import mrkd

/// Agent tag pairs such as `<thinking>` … `</thinking>` render as a labelled
/// box with the markdown between the tags rendered inside it.
final class AgentTagBlockTests: XCTestCase {

    // MARK: - Helpers

    private func render(_ markdown: String, theme: Theme = DefaultTheme()) -> NSAttributedString {
        MarkdownRenderer.render(markdown, theme: theme)
    }

    /// Location of the first character of `text` in the rendered string.
    private func location(of text: String, in rendered: NSAttributedString) -> Int? {
        let range = (rendered.string as NSString).range(of: text)
        return range.location == NSNotFound ? nil : range.location
    }

    private func textBlocks(at location: Int, in rendered: NSAttributedString) -> [NSTextBlock] {
        let style = rendered.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        return style?.textBlocks ?? []
    }

    /// The box a label starts: the outermost text block on the label's line.
    /// A label is the tag name alone on its line.
    private func box(labelled name: String, in rendered: NSAttributedString) -> NSTextBlock? {
        let text = rendered.string as NSString
        var searchFrom = 0
        while searchFrom < text.length {
            let found = text.range(of: name, range: NSRange(location: searchFrom, length: text.length - searchFrom))
            guard found.location != NSNotFound else { return nil }
            let line = text.paragraphRange(for: found)
            let lineText = text.substring(with: line).trimmingCharacters(in: .newlines)
            if lineText == name {
                return textBlocks(at: found.location, in: rendered).last
            }
            searchFrom = NSMaxRange(found)
        }
        return nil
    }

    private func isInside(_ box: NSTextBlock, text: String, in rendered: NSAttributedString) -> Bool {
        guard let at = location(of: text, in: rendered) else { return false }
        return textBlocks(at: at, in: rendered).contains { $0 === box }
    }

    private func headingLevel(of text: String, in rendered: NSAttributedString) -> Int? {
        guard let at = location(of: text, in: rendered) else { return nil }
        return rendered.attribute(.accessibilityHeadingLevel, at: at, effectiveRange: nil) as? Int
    }

    // MARK: - Tight and spaced forms

    func testTightThinkingBlockRendersAsALabelledBoxOfMarkdown() {
        let rendered = render("""
        Intro.

        <thinking>
        ## Plan
        - read the file
        - fix the **bug**
        </thinking>

        After.
        """)

        XCTAssertFalse(rendered.string.contains("<thinking>"), "the open tag must not show as text")
        XCTAssertFalse(rendered.string.contains("</thinking>"), "the close tag must not show as text")
        guard let box = box(labelled: "thinking", in: rendered) else {
            return XCTFail("no box labelled 'thinking' in: \(rendered.string)")
        }
        XCTAssertEqual(headingLevel(of: "Plan", in: rendered), 2, "the heading inside must render as a heading")
        XCTAssertTrue(isInside(box, text: "Plan", in: rendered))
        XCTAssertTrue(isInside(box, text: "read the file", in: rendered))
        XCTAssertTrue(rendered.string.contains("\u{2022}"), "the list inside must render with bullets")
        XCTAssertFalse(rendered.string.contains("**"), "emphasis inside must render, not show its markers")
        XCTAssertFalse(isInside(box, text: "Intro.", in: rendered))
        XCTAssertFalse(isInside(box, text: "After.", in: rendered))
    }

    func testSpacedThinkingBlockRendersAsALabelledBoxOfMarkdown() {
        let rendered = render("""
        <thinking>

        First thought.

        Second thought.

        </thinking>

        After.
        """)

        XCTAssertFalse(rendered.string.contains("<thinking>"))
        XCTAssertFalse(rendered.string.contains("</thinking>"))
        guard let box = box(labelled: "thinking", in: rendered) else {
            return XCTFail("no box labelled 'thinking' in: \(rendered.string)")
        }
        XCTAssertTrue(isInside(box, text: "First thought.", in: rendered))
        XCTAssertTrue(isInside(box, text: "Second thought.", in: rendered))
        XCTAssertFalse(isInside(box, text: "After.", in: rendered))
    }

    func testTightBlockWithABlankLineInsideStaysOneBox() {
        let rendered = render("<answer>\nFirst part.\n\nSecond part.\n</answer>")
        guard let box = box(labelled: "answer", in: rendered) else {
            return XCTFail("no box labelled 'answer' in: \(rendered.string)")
        }
        XCTAssertTrue(isInside(box, text: "First part.", in: rendered))
        XCTAssertTrue(isInside(box, text: "Second part.", in: rendered))
    }

    func testCodeAndMathInsideABoxRender() {
        let rendered = render("<analysis>\n```swift\nlet x = 1\n```\n$$x^2$$\n</analysis>")
        guard let box = box(labelled: "analysis", in: rendered) else {
            return XCTFail("no box labelled 'analysis' in: \(rendered.string)")
        }
        XCTAssertTrue(isInside(box, text: "let x = 1", in: rendered))
        XCTAssertFalse(rendered.string.contains("```"), "the fence inside must render as code")
        XCTAssertFalse(rendered.string.contains("$$"), "the formula inside must render as math")
    }

    // MARK: - Names and attributes

    func testAttributesAreLeftOutOfTheLabel() {
        let rendered = render("<example index=\"1\" kind='short'>\nAn example.\n</example>")
        XCTAssertFalse(rendered.string.contains("index"), "attributes must not show")
        guard let box = box(labelled: "example", in: rendered) else {
            return XCTFail("no box labelled 'example' in: \(rendered.string)")
        }
        XCTAssertTrue(isInside(box, text: "An example.", in: rendered))
    }

    func testHyphenAndUnderscoreNamesAreBoxed() {
        let rendered = render("<system-reminder>\nBe brief.\n</system-reminder>\n\n<search_results>\nNone.\n</search_results>")
        XCTAssertNotNil(box(labelled: "system-reminder", in: rendered), rendered.string)
        XCTAssertNotNil(box(labelled: "search_results", in: rendered), rendered.string)
    }

    // MARK: - Real HTML and other cases keep today's behaviour

    func testHTMLElementsKeepRenderingAsBefore() {
        for name in ["div", "details", "DIV", "section", "search", "center"] {
            let source = "<\(name)>\nhello\n</\(name)>\n\nAfter."
            let rendered = render(source)
            XCTAssertTrue(rendered.string.contains("<\(name)>"), "<\(name)> must still show as raw HTML")
            XCTAssertTrue(rendered.string.contains("</\(name)>"), "</\(name)> must still show as raw HTML")
            XCTAssertNil(box(labelled: name, in: rendered), "<\(name)> is HTML and must not become a box")
            XCTAssertEqual(BlockSplitter.split(source), ["<\(name)>\nhello\n</\(name)>", "After."])
        }
    }

    func testTagsInsideAFencedCodeBlockStayCode() {
        let source = "```\n<thinking>\nnot a box\n</thinking>\n```"
        let rendered = render(source)
        XCTAssertTrue(rendered.string.contains("<thinking>\nnot a box\n</thinking>"))
        XCTAssertNil(box(labelled: "thinking", in: rendered))
        XCTAssertEqual(BlockSplitter.split(source), [source])
    }

    func testAnOpenTagWithoutACloseKeepsTodaysBehaviour() {
        let source = "<thinking>\nstill thinking"
        let rendered = render(source)
        XCTAssertTrue(rendered.string.contains("<thinking>"))
        XCTAssertNil(box(labelled: "thinking", in: rendered))
        XCTAssertEqual(BlockSplitter.split(source), [source])
    }

    func testIndentedTagsAreNotTopLevel() {
        let source = "- item\n  <thinking>\n  inside the list\n  </thinking>"
        XCTAssertEqual(BlockSplitter.split(source), [source])
        XCTAssertNil(box(labelled: "thinking", in: render(source)))
    }

    // MARK: - Nesting

    func testNestedPairsRenderAsBoxesInsideBoxes() {
        let rendered = render("""
        <outer>
        Outer text.
        <inner>
        Inner text.
        </inner>
        More outer text.
        </outer>
        """)
        guard let outer = box(labelled: "outer", in: rendered),
              let inner = box(labelled: "inner", in: rendered) else {
            return XCTFail("missing a box in: \(rendered.string)")
        }
        XCTAssertFalse(outer === inner)
        XCTAssertTrue(isInside(outer, text: "Outer text.", in: rendered))
        XCTAssertTrue(isInside(outer, text: "Inner text.", in: rendered))
        XCTAssertTrue(isInside(inner, text: "Inner text.", in: rendered))
        XCTAssertFalse(isInside(inner, text: "Outer text.", in: rendered))
        XCTAssertTrue(isInside(outer, text: "More outer text.", in: rendered))
        XCTAssertFalse(isInside(inner, text: "More outer text.", in: rendered))
    }

    // MARK: - Source blocks, contents and progressive render

    func testTagLinesAreBlocksOfTheirOwn() {
        XCTAssertEqual(
            BlockSplitter.split("Intro.\n<thinking>\nreason\n</thinking>\nAfter."),
            ["Intro.", "<thinking>", "reason", "</thinking>", "After."]
        )
    }

    func testEveryRenderedRunPointsAtTheBlockItCameFrom() {
        let source = "<thinking>\nreason\n</thinking>\n\nAfter."
        let blocks = BlockSplitter.split(source)
        let rendered = render(source)

        func sourceBlock(of text: String) -> String? {
            guard let at = location(of: text, in: rendered),
                  let index = rendered.attribute(.sourceBlockIndex, at: at, effectiveRange: nil) as? Int,
                  blocks.indices.contains(index) else { return nil }
            return blocks[index]
        }
        XCTAssertEqual(sourceBlock(of: "reason"), "reason")
        XCTAssertEqual(sourceBlock(of: "After."), "After.", "the block after a tag pair must keep its own index")
        XCTAssertEqual(sourceBlock(of: "thinking"), "<thinking>", "the label belongs to the open tag")
    }

    /// Front matter takes the first block, so every tag pair after it sits
    /// one block further on. The pairs and the source indices must both
    /// count it.
    func testATagPairAfterFrontMatterIsStillABox() {
        let source = "---\ntitle: Plan\n\nstatus: draft\n---\n<thinking>\nreason\n</thinking>\n\nAfter."
        let blocks = BlockSplitter.split(source)
        XCTAssertEqual(blocks, ["---\ntitle: Plan\n\nstatus: draft\n---", "<thinking>", "reason", "</thinking>", "After."])

        let rendered = render(source)
        let thinking = box(labelled: "thinking", in: rendered)
        XCTAssertNotNil(thinking, "the pair after front matter must still be a box")
        if let thinking {
            XCTAssertTrue(isInside(thinking, text: "reason", in: rendered))
            XCTAssertFalse(isInside(thinking, text: "title: Plan", in: rendered))
        }
        let after = location(of: "After.", in: rendered)!
        XCTAssertEqual(rendered.attribute(.sourceBlockIndex, at: after, effectiveRange: nil) as? Int, 4)
    }

    func testHeadingsInsideABoxReachTheContents() {
        let rendered = render("# Report\n\n<thinking>\n## Inside the box\nText.\n</thinking>")
        let titles = TOCBuilder.build(from: rendered).map(\.text)
        XCTAssertEqual(titles, ["Report", "Inside the box"])
    }

    func testProgressiveRenderMatchesTheOnePassRender() {
        let source = "Intro.\n\n<thinking>\nOne.\n\nTwo.\n</thinking>\n\nAfter."
        var firstScreen: NSAttributedString?
        let progressive = MarkdownRenderer.renderProgressive(source, firstScreenBlocks: 1) { firstScreen = $0 }
        XCTAssertEqual(progressive.string, render(source).string)
        XCTAssertEqual(
            firstScreen?.string.trimmingCharacters(in: .newlines),
            "Intro.",
            "a first screen holds whole top-level blocks"
        )
    }

    // MARK: - Theme

    func testTheBoxIsDrawnInTheThemesOwnColours() {
        for theme in [DefaultTheme(), GitHubDark(), HighContrastTheme(wrapping: GitHubLight())] as [Theme] {
            let rendered = render("<example>\nText.\n</example>", theme: theme)
            guard let box = box(labelled: "example", in: rendered),
                  let label = location(of: "example", in: rendered) else {
                return XCTFail("no box for \(theme.name)")
            }
            XCTAssertEqual(box.borderColor(for: .minX), theme.blockquoteBarColor, theme.name)
            XCTAssertEqual(box.borderColor(for: .maxY), theme.blockquoteBarColor, theme.name)
            XCTAssertNil(box.backgroundColor, "no fill, so code blocks inside keep theirs (\(theme.name))")
            XCTAssertEqual(
                rendered.attribute(.foregroundColor, at: label, effectiveRange: nil) as? NSColor,
                theme.textColor,
                "the label is body text colour, which every theme already holds to AA (\(theme.name))"
            )
        }
    }

    /// An agent's reasoning is not what it hands over, so it sits back from
    /// the page: a grey fill and muted text, as agent apps show thinking.
    func testReasoningIsMutedOnAGreyFill() {
        for name in ["thinking", "think", "reasoning", "scratchpad", "Thinking"] {
            let theme = GitHubDark()
            let rendered = render("<\(name)>\nWorking it out.\n</\(name)>\n\nThe answer.", theme: theme)
            guard let box = box(labelled: name, in: rendered),
                  let text = location(of: "Working it out.", in: rendered),
                  let answer = location(of: "The answer.", in: rendered) else {
                return XCTFail("no box for <\(name)>")
            }
            XCTAssertEqual(box.backgroundColor, theme.codeBackgroundColor, name)
            XCTAssertEqual(box.width(for: .border, edge: .minX), 0, "a fill, not an outline (\(name))")
            let muted = rendered.attribute(.foregroundColor, at: text, effectiveRange: nil) as? NSColor
            XCTAssertNotNil(muted, name)
            XCTAssertNotEqual(muted, theme.textColor, "reasoning is muted (\(name))")
            XCTAssertEqual(rendered.attribute(.foregroundColor, at: answer, effectiveRange: nil) as? NSColor,
                           theme.textColor, "only the reasoning is muted (\(name))")
        }
    }

    /// Muted is not unreadable: the muted text on the grey fill still meets
    /// WCAG AA (4.5:1) in every built-in theme, light and dark.
    func testMutedReasoningTextMeetsAAInEveryTheme() {
        let themes: [Theme] = [
            DefaultTheme(), GitHubLight(), GitHubDark(), MonokaiTheme(), CatppuccinMochaTheme(), SnazzyTheme(),
            HighContrastTheme(wrapping: GitHubLight()), HighContrastTheme(wrapping: GitHubDark()),
        ]
        for theme in themes {
            let rendered = render("<thinking>\nWorking it out.\n</thinking>", theme: theme)
            guard let box = box(labelled: "thinking", in: rendered),
                  let at = location(of: "Working it out.", in: rendered),
                  let muted = rendered.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor,
                  let fillColor = box.backgroundColor else {
                return XCTFail("no muted box for \(theme.name)")
            }
            for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
                NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
                    let page = Self.opaque(theme.backgroundColor, over: .white)
                    let fill = Self.opaque(fillColor, over: page)
                    let text = Self.opaque(muted, over: fill)
                    let full = Self.opaque(theme.textColor, over: fill)
                    let ratio = Self.contrast(text, fill)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme.name) in \(appearanceName.rawValue): \(ratio)")
                    XCTAssertLessThan(ratio, Self.contrast(full, fill),
                                      "muted must be quieter than body text (\(theme.name), \(appearanceName.rawValue))")
                }
            }
        }
    }

    private static func opaque(_ color: NSColor, over base: NSColor) -> NSColor {
        let c = color.usingColorSpace(.sRGB)!, b = base.usingColorSpace(.sRGB)!
        let a = c.alphaComponent
        return NSColor(srgbRed: c.redComponent * a + b.redComponent * (1 - a),
                       green: c.greenComponent * a + b.greenComponent * (1 - a),
                       blue: c.blueComponent * a + b.blueComponent * (1 - a), alpha: 1)
    }

    private static func contrast(_ x: NSColor, _ y: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            let c = color.usingColorSpace(.sRGB)!
            func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
        }
        let (l1, l2) = (luminance(x), luminance(y))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
