import XCTest
import AppKit
@testable import mrkd

@MainActor
final class ThemePickerGridTests: XCTestCase {

    private func previewTextViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        func walk(_ v: NSView) {
            if let textView = v as? NSTextView, textView.string.contains("Heading") { found.append(textView) }
            v.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    /// TextKit 2 fails to lay out text blocks, which every code block uses,
    /// so the document view runs on TextKit 1. A plain NSTextView starts on
    /// TextKit 2: in the 1.5.0 release, built with the macOS 15.5 SDK, every
    /// card showed only its background colour. The previews use the same
    /// TextKit 1 stack as the document, from the start.
    func testPreviewsUseTheDocumentsTextKit1Stack() {
        _ = NSApplication.shared
        let grid = ThemePickerGridView(selectedTheme: "Default")
        let previews = previewTextViews(in: grid)
        XCTAssertFalse(previews.isEmpty)
        for preview in previews {
            XCTAssertNil(preview.textLayoutManager, "TextKit 2 cannot lay out code blocks")
            XCTAssertTrue(preview.layoutManager is CodeBorderLayoutManager, "the document's own layout manager")
        }
    }

    /// Each card previews its theme with sample text. The text view must
    /// get its size from the card itself. Left to a scroll view to size, it
    /// stayed zero wide in the release build, made with an older macOS SDK,
    /// and every card showed only its background colour.
    func testEveryCardPreviewIsLaidOutAtTheCardsSize() {
        _ = NSApplication.shared
        let grid = ThemePickerGridView(selectedTheme: "Default")
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        host.addSubview(grid)
        host.layoutSubtreeIfNeeded()

        let previews = previewTextViews(in: grid)
        XCTAssertFalse(previews.isEmpty)
        for preview in previews {
            XCTAssertGreaterThan(preview.frame.width, 100, "preview text is \(preview.frame.width) wide")
            XCTAssertGreaterThan(preview.frame.height, 50, "preview text is \(preview.frame.height) high")
            XCTAssertGreaterThan(preview.textContainer?.size.width ?? 0, 100, "text wraps at the card's width")
        }
    }
}
