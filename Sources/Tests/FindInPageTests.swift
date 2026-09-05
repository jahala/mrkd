import XCTest
import AppKit
@testable import mrkd

/// Find-in-page end to end: a real document on disk, a real `NSTextView`
/// find bar, real searches. The controller is hosted in a real (offscreen)
/// window, the same way `LiveReloadTests` does it, because the find bar
/// lives in the scroll view and the reading position depends on geometry.
@MainActor
final class FindInPageTests: XCTestCase {

    private var tempDir: URL!
    private var windows: [NSWindow] = []
    private var savedFindString: String?
    private var savedTheme: String?
    private var savedDefaultsTheme: Any?
    private var savedAppAppearance: NSAppearance?

    private static let appID = "com.mrkd.app" as CFString

    override func setUp() async throws {
        // Bring the shared application up before anything reads `NSApp`;
        // these tests can be the first thing to run in the process.
        _ = NSApplication.shared
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-find-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Searching writes the machine's shared find string; put it back.
        savedFindString = NSPasteboard(name: .find).string(forType: .string)
        savedTheme = CFPreferencesCopyAppValue("selectedTheme" as CFString, Self.appID) as? String
        savedDefaultsTheme = UserDefaults.standard.object(forKey: "selectedTheme")
        savedAppAppearance = NSApp.appearance
    }

    override func tearDown() async throws {
        for window in windows { window.contentViewController = nil }
        windows.removeAll()
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        if let savedFindString { pasteboard.setString(savedFindString, forType: .string) }
        CFPreferencesSetAppValue(
            "selectedTheme" as CFString,
            savedTheme as CFPropertyList?,
            Self.appID
        )
        CFPreferencesAppSynchronize(Self.appID)
        UserDefaults.standard.set(savedDefaultsTheme, forKey: "selectedTheme")
        NSApp.appearance = savedAppAppearance
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func writeFixture(name: String, contents: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = 6, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }

    private func makeController(for url: URL) -> MarkdownViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let vc = MarkdownViewController(fileURL: url)
        window.contentViewController = vc
        window.setContentSize(NSSize(width: 1000, height: 800))
        window.layoutIfNeeded()
        windows.append(window)
        return vc
    }

    /// Occurrences of `needle`, worked out independently of the code under
    /// test so the expectations are not written by the implementation.
    private func occurrences(of needle: String, in text: String) -> [NSRange] {
        let string = text as NSString
        var found: [NSRange] = []
        var start = 0
        while start < string.length {
            let range = string.range(
                of: needle,
                options: [],
                range: NSRange(location: start, length: string.length - start)
            )
            if range.location == NSNotFound { break }
            found.append(range)
            start = NSMaxRange(range)
        }
        return found
    }

    private func selectedText(in textView: NSTextView) -> String {
        (textView.string as NSString).substring(with: textView.selectedRange())
    }

    /// Drive a search the way `Cmd E` then `Cmd G` does: take the search
    /// string from a selection, then step to the first match.
    private func search(_ needle: String, in vc: MarkdownViewController, textView: NSTextView) {
        guard let first = occurrences(of: needle, in: textView.string).first else {
            return XCTFail("fixture does not contain \(needle)")
        }
        textView.setSelectedRange(first)
        vc.useSelectionForFind(nil)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        vc.findNext(nil)
    }

    private func setTheme(_ name: String) {
        CFPreferencesSetAppValue("selectedTheme" as CFString, name as CFString, Self.appID)
        CFPreferencesAppSynchronize(Self.appID)
    }

    private func commandF(in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "f",
            charactersIgnoringModifiers: "f",
            isARepeat: false,
            keyCode: 3
        )!
    }

    private let filler = (1...30)
        .map { "Filler paragraph \($0) with enough words in it to take up a line.\n" }
        .joined(separator: "\n")

    // MARK: - Searching

    func testFindNextAndFindPreviousWalkTheMatches() throws {
        let url = try writeFixture(
            name: "search.md",
            contents: "# Doc\n\nalpha needle beta\n\ngamma needle delta\n\nlast needle here\n"
        )
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view) else {
            return XCTFail("controller did not build its text view")
        }
        XCTAssertTrue(waitUntil { textView.string.contains("last needle here") },
                      "initial render never completed")

        let matches = occurrences(of: "needle", in: textView.string)
        XCTAssertEqual(matches.count, 3, "fixture should render three matches")

        search("needle", in: vc, textView: textView)
        XCTAssertEqual(textView.selectedRange(), matches[0], "Find Next should land on the first match")

        vc.findNext(nil)
        XCTAssertEqual(textView.selectedRange(), matches[1])

        vc.findNext(nil)
        XCTAssertEqual(textView.selectedRange(), matches[2])

        vc.findPrevious(nil)
        XCTAssertEqual(textView.selectedRange(), matches[1], "Find Previous should walk back")
    }

    // MARK: - Theming

    func testFindBarFollowsTheDocumentThemeNotTheWindow() throws {
        let url = try writeFixture(name: "themed.md", contents: "# Doc\n\nbody text\n")
        setTheme("Catppuccin Mocha")
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view) else {
            return XCTFail("controller did not build its text view")
        }
        XCTAssertTrue(waitUntil { textView.string.contains("body text") },
                      "initial render never completed")

        // Force the window light. Catppuccin Mocha is dark in every system
        // appearance, so a bar that followed its surroundings comes out
        // aqua and a bar that follows the document comes out dark.
        vc.view.window?.appearance = NSAppearance(named: .aqua)
        vc.showFindBar(nil)
        XCTAssertTrue(waitUntil { vc.findController.findBarView != nil },
                      "the find bar never appeared")
        let bar = try XCTUnwrap(vc.findController.findBarView)
        XCTAssertEqual(
            bar.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
            .darkAqua,
            "a dark document must not get a light find bar"
        )

        // And the other way round, so this cannot pass by accident on a
        // machine that happens to be in dark mode.
        vc.findController.applyTheme(GitHubLight())
        XCTAssertEqual(
            bar.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
            .aqua,
            "a light document must not get a dark find bar"
        )
    }

    func testChangingTheThemeRepaintsAnOpenFindBar() throws {
        // Resolve GitHub to its light variant deterministically, whatever
        // the machine is set to.
        NSApp.appearance = NSAppearance(named: .aqua)
        setTheme("GitHub")
        let url = try writeFixture(name: "retheme.md", contents: "# Doc\n\nbody text\n")
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view) else {
            return XCTFail("controller did not build its text view")
        }
        XCTAssertTrue(waitUntil { textView.string.contains("body text") },
                      "initial render never completed")

        vc.showFindBar(nil)
        XCTAssertTrue(waitUntil { vc.findController.findBarView != nil },
                      "the find bar never appeared")
        let bar = try XCTUnwrap(vc.findController.findBarView)
        XCTAssertEqual(bar.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)

        // Switching to a dark theme with the bar already open has to
        // repaint it; a light bar over a dark document is the bug.
        let backgroundBefore = textView.backgroundColor
        ThemeManager.shared.selectedThemeName = "Catppuccin Mocha"
        XCTAssertTrue(
            waitUntil { textView.backgroundColor != backgroundBefore },
            "the theme change never re-rendered"
        )
        XCTAssertEqual(
            bar.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
            .darkAqua,
            "an open find bar must follow the theme it is switched to"
        )
    }

    // MARK: - Live reload

    func testTheActiveMatchSurvivesALiveReloadThatMovesIt() throws {
        let before = "# Doc\n\n\(filler)\nneedle one\n\n\(filler)\nneedle two\n"
        let url = try writeFixture(name: "reload-find.md", contents: before)
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view) else {
            return XCTFail("controller did not build its text view")
        }
        XCTAssertTrue(waitUntil { textView.string.contains("needle two") },
                      "initial render never completed")

        // Walk to the *second* match, the one the reader is on.
        search("needle", in: vc, textView: textView)
        vc.findNext(nil)
        let matchesBefore = occurrences(of: "needle", in: textView.string)
        XCTAssertEqual(textView.selectedRange(), matchesBefore[1])

        // Insert above both matches, so every character offset below moves.
        let grown = "# Doc\n\nAn inserted opening paragraph that pushes the whole document down.\n\n\(filler)\nneedle one\n\n\(filler)\nneedle two\n"
        try grown.write(to: url, atomically: false, encoding: .utf8)

        XCTAssertTrue(
            waitUntil { textView.string.contains("An inserted opening paragraph") },
            "the live reload never ran — a find match must not hold it back"
        )
        XCTAssertFalse(
            vc.isLiveReloadHeldBySelection,
            "a find match is the search's selection, not the reader's"
        )

        let matchesAfter = occurrences(of: "needle", in: textView.string)
        XCTAssertEqual(matchesAfter.count, 2)
        XCTAssertGreaterThan(
            matchesAfter[1].location, matchesBefore[1].location,
            "the fixture must actually move the match down the document, or surviving the reload proves nothing"
        )
        XCTAssertEqual(
            textView.selectedRange(),
            matchesAfter[1],
            "the reload should leave the reader on their own match, not the first one"
        )
    }

    func testAnOpenFindBarDoesNotLetASelectionFreezeTheDocument() throws {
        let url = try writeFixture(name: "barheld.md", contents: "# Doc\n\nfirst body paragraph.\n")
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view) else {
            return XCTFail("controller did not build its text view")
        }
        XCTAssertTrue(waitUntil { textView.string.contains("first body paragraph") },
                      "initial render never completed")

        vc.showFindBar(nil)
        XCTAssertTrue(waitUntil { vc.findController.isFindBarVisible }, "the find bar never appeared")

        // Incremental searching selects as the reader types; the selection
        // on screen while the bar is open belongs to the search.
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        try "# Doc\n\nrewritten body paragraph.\n".write(to: url, atomically: false, encoding: .utf8)

        XCTAssertTrue(
            waitUntil { textView.string.contains("rewritten body paragraph") },
            "a selection made while the find bar is open must not hold the reload"
        )
        XCTAssertFalse(vc.isLiveReloadHeldBySelection)
    }

    func testAReaderSelectionAfterASearchStillHoldsTheReload() throws {
        let url = try writeFixture(
            name: "handback.md",
            contents: "# Doc\n\nalpha needle beta\n\nmore body text here\n"
        )
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view) else {
            return XCTFail("controller did not build its text view")
        }
        XCTAssertTrue(waitUntil { textView.string.contains("more body text here") },
                      "initial render never completed")

        search("needle", in: vc, textView: textView)
        XCTAssertFalse(vc.findController.isFindBarVisible, "this flow never opens the bar")

        // Having searched, the reader now drags a selection of their own.
        // That is work in progress again, and it must hold the reload back
        // exactly as it would have before they searched.
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        try "# Doc\n\nalpha needle beta\n\nrewritten body text here\n"
            .write(to: url, atomically: false, encoding: .utf8)

        XCTAssertTrue(
            waitUntil { vc.isLiveReloadHeldBySelection },
            "a selection the reader made after searching must still hold the reload"
        )
        XCTAssertFalse(textView.string.contains("rewritten body text"))

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(
            waitUntil { textView.string.contains("rewritten body text") },
            "clearing the selection should release the held reload"
        )
    }

    func testChangingTheThemeKeepsTheFindMatch() throws {
        setTheme("GitHub")
        let url = try writeFixture(
            name: "rerender.md",
            contents: "# Doc\n\n\(filler)\nneedle one\n\n\(filler)\nneedle two\n"
        )
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view) else {
            return XCTFail("controller did not build its text view")
        }
        XCTAssertTrue(waitUntil { textView.string.contains("needle two") },
                      "initial render never completed")

        search("needle", in: vc, textView: textView)
        vc.findNext(nil)
        let expected = occurrences(of: "needle", in: textView.string)[1]
        XCTAssertEqual(textView.selectedRange(), expected)

        // A theme change replaces the text storage exactly as a reload does.
        let backgroundBefore = textView.backgroundColor
        ThemeManager.shared.selectedThemeName = "Catppuccin Mocha"
        XCTAssertTrue(
            waitUntil { textView.backgroundColor != backgroundBefore },
            "the theme change never re-rendered"
        )

        XCTAssertEqual(
            textView.selectedRange(), expected,
            "re-rendering for a new theme dropped the reader's match"
        )
        XCTAssertEqual(selectedText(in: textView), "needle")
    }

    // MARK: - Hosts without a menu bar

    func testCommandFOpensTheFindBarOnlyWhereTheHostAsksForIt() throws {
        let url = try writeFixture(name: "keyequiv.md", contents: "# Doc\n\nbody text\n")
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view) else {
            return XCTFail("controller did not build its text view")
        }
        XCTAssertTrue(waitUntil { textView.string.contains("body text") },
                      "initial render never completed")
        let window = try XCTUnwrap(vc.view.window)
        let event = commandF(in: window)

        XCTAssertFalse(
            window.performKeyEquivalent(with: event),
            "in the app Cmd-F belongs to the Edit menu, not to the view hierarchy"
        )
        XCTAssertFalse(vc.findController.isFindBarVisible)

        // The Quick Look preview has no menu bar and opts in.
        vc.handlesFindKeyEquivalents = true
        XCTAssertTrue(
            window.performKeyEquivalent(with: event),
            "a host without a menu bar must be able to open the find bar with Cmd-F"
        )
        XCTAssertTrue(waitUntil { vc.findController.isFindBarVisible })
    }
}
