import XCTest
import AppKit
@testable import mrkd

/// One darkness rule for a theme, shared by the syntax-highlighting theme
/// and the find bar's appearance.
final class ThemeDarknessTests: XCTestCase {

    func testIsDarkFollowsTheDocumentBackground() {
        // Catppuccin Mocha's base is #1e1e2e; GitHub Light's is #ffffff.
        XCTAssertTrue(CatppuccinMochaTheme().isDark)
        XCTAssertTrue(MonokaiTheme().isDark)
        XCTAssertTrue(GitHubDark().isDark)
        XCTAssertFalse(GitHubLight().isDark)
    }

    func testTheDefaultSyntaxThemeFollowsTheSameRule() {
        // A theme that does not name a Highlightr theme inherits one from
        // its own background, using the same rule — not a second one.
        XCTAssertEqual(PlainTheme(background: .black).highlightrTheme, "atom-one-dark")
        XCTAssertEqual(PlainTheme(background: .white).highlightrTheme, "atom-one-light")
    }
}

/// A theme with nothing but a background colour, so the protocol's own
/// defaults are what is under test.
private struct PlainTheme: Theme {
    let name = "Plain"
    let baseFontSize: CGFloat = 13
    let fontFamily = "SF Mono"
    let background: NSColor

    var backgroundColor: NSColor { background }
    var textColor: NSColor { .labelColor }
    var linkColor: NSColor { .linkColor }
    var codeBackgroundColor: NSColor { .gray }
    var codeTextColor: NSColor { .labelColor }
    var blockquoteColor: NSColor { .gray }
    var blockquoteBarColor: NSColor { .gray }

    func headingColor(level: Int) -> NSColor { .labelColor }
}
