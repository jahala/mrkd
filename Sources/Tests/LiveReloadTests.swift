import XCTest
import AppKit
@testable import mrkd

/// End-to-end live-reload behaviour: a real file on disk, a real FileWatcher,
/// a real render pipeline. Nothing here is mocked — the tests write to the
/// file and spin the main run loop until the view catches up.
@MainActor
final class LiveReloadTests: XCTestCase {

    private var tempDir: URL!
    private var windows: [NSWindow] = []

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for window in windows { window.contentViewController = nil }
        windows.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func writeFixture(name: String, contents: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Spin the main run loop until `condition` holds or the timeout expires.
    /// Main-queue work (render completions, watcher callbacks) drains here.
    @discardableResult
    private func waitUntil(
        timeout: TimeInterval = 6,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func spinRunLoop(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func bannerPresent(in view: NSView) -> Bool {
        if view is ReloadBannerView { return true }
        return view.subviews.contains { bannerPresent(in: $0) }
    }

    private func gutterView(in view: NSView) -> ChangedBlockGutterView? {
        if let gutter = view as? ChangedBlockGutterView { return gutter }
        for subview in view.subviews {
            if let found = gutterView(in: subview) { return found }
        }
        return nil
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }

    /// Hosted in a real (offscreen) window. Without one the text view never
    /// grows past the viewport, so scroll geometry is meaningless and the
    /// reading-position tests would be measuring nothing.
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

    // MARK: - Tests

    /// The core of task 1: an external write re-renders the document by
    /// itself, with no banner and no user click.
    func testExternalWriteAutoReloadsWithoutBanner() throws {
        let url = try writeFixture(name: "live.md", contents: "# Before\n\nbody text\n")
        let vc = makeController(for: url)
        XCTAssertTrue(
            waitUntil { vc.tocEntries.first?.text == "Before" },
            "initial render never completed"
        )

        try "# After\n\nbody text\n".write(to: url, atomically: false, encoding: .utf8)

        XCTAssertTrue(
            waitUntil { vc.tocEntries.first?.text == "After" },
            "external write did not auto-reload the document"
        )
        XCTAssertFalse(
            bannerPresent(in: vc.view),
            "auto-reload must not put up a reload banner"
        )
    }

    /// An atomic save (write to a temp file, rename over the original) is how
    /// most editors and agents write. The path is valid again immediately, so
    /// it must reload rather than claim the file was deleted.
    func testAtomicSaveReloadsAndShowsNoDeletionBanner() throws {
        let url = try writeFixture(name: "atomic.md", contents: "# Before\n\nbody\n")
        let vc = makeController(for: url)
        XCTAssertTrue(
            waitUntil { vc.tocEntries.first?.text == "Before" },
            "initial render never completed"
        )

        try "# Rewritten\n\nbody\n".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertTrue(
            waitUntil { vc.tocEntries.first?.text == "Rewritten" },
            "atomic save did not auto-reload the document"
        )
        XCTAssertFalse(
            bannerPresent(in: vc.view),
            "an atomic save is a write, not a deletion — no banner"
        )
    }

    /// A live text selection is the user's work; reloading destroys it.
    /// The reload is held, then applied the moment the selection clears.
    func testSelectionHoldsReloadUntilCleared() throws {
        let url = try writeFixture(name: "selected.md", contents: "# Before\n\nsome body text\n")
        let vc = makeController(for: url)
        XCTAssertTrue(
            waitUntil { vc.tocEntries.first?.text == "Before" },
            "initial render never completed"
        )
        guard let textView = textView(in: vc.view) else {
            return XCTFail("no text view in the controller's view hierarchy")
        }

        textView.setSelectedRange(NSRange(location: 0, length: 4))
        try "# After\n\nsome body text\n".write(to: url, atomically: false, encoding: .utf8)

        XCTAssertTrue(
            waitUntil { vc.isLiveReloadHeldBySelection },
            "a change during a selection should be held, not applied"
        )
        XCTAssertEqual(
            vc.tocEntries.first?.text, "Before",
            "reload must not run while text is selected"
        )

        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(
            waitUntil { vc.tocEntries.first?.text == "After" },
            "clearing the selection should release the held reload"
        )
        XCTAssertFalse(vc.isLiveReloadHeldBySelection)
    }

    /// Deletion keeps its explicit banner — that is the one case the user has
    /// to be told about, because there is nothing to render.
    func testDeletionStillShowsBanner() throws {
        let url = try writeFixture(name: "doomed.md", contents: "# Doomed\n\nbody\n")
        let vc = makeController(for: url)
        XCTAssertTrue(
            waitUntil { vc.tocEntries.first?.text == "Doomed" },
            "initial render never completed"
        )

        try FileManager.default.removeItem(at: url)

        XCTAssertTrue(
            waitUntil { self.bannerPresent(in: vc.view) },
            "deleting the file should show the deletion banner"
        )
    }

    /// Reading position survives a reload that changes the length of the
    /// document above the viewport. The assertion that matters is the
    /// heading's *on-screen* offset: the reader must see the "Target"
    /// heading in the same place, not merely somewhere near it.
    func testReloadKeepsReadingPositionAnchoredToHeading() throws {
        let filler = (1...40).map { "Paragraph \($0) of the introduction.\n" }.joined(separator: "\n")
        let tail = (1...40).map { "Trailing paragraph \($0).\n" }.joined(separator: "\n")
        let before = "# Top\n\n\(filler)\n## Target\n\ntarget body\n\n\(tail)"
        let url = try writeFixture(name: "anchor.md", contents: before)
        let vc = makeController(for: url)
        XCTAssertTrue(
            waitUntil { vc.tocEntries.count >= 2 },
            "initial render never completed"
        )

        guard let target = vc.tocEntries.first(where: { $0.text == "Target" }) else {
            return XCTFail("fixture should contain a Target heading")
        }
        vc.scrollToHeading(target)
        spinRunLoop(for: 0.1)
        let anchoredBefore = vc.currentReadingAnchor()
        XCTAssertEqual(anchoredBefore.heading?.text, "Target")
        let locationBefore = target.location

        // Double the introduction. Everything below it shifts down by well
        // over a screenful, so an absolute-offset restore lands in the middle
        // of the new filler and a proportional restore lands somewhere else
        // again — only following the heading keeps the offset.
        let grown = "# Top\n\n\(filler)\n\(filler)\n## Target\n\ntarget body\n\n\(tail)"
        try grown.write(to: url, atomically: false, encoding: .utf8)

        XCTAssertTrue(
            waitUntil {
                (vc.tocEntries.first(where: { $0.text == "Target" })?.location ?? locationBefore) > locationBefore
            },
            "the grown document never rendered"
        )

        let anchoredAfter = vc.currentReadingAnchor()
        XCTAssertEqual(anchoredAfter.heading?.text, "Target")
        XCTAssertEqual(
            anchoredAfter.offsetFromHeading,
            anchoredBefore.offsetFromHeading,
            accuracy: 4,
            "the Target heading moved on screen: reading position was not preserved"
        )
    }

    // MARK: - Changed-block accent

    /// Task 2: editing one paragraph of a document accents that paragraph and
    /// nothing else, at the paragraph's own vertical position.
    func testReloadAccentsOnlyTheChangedParagraph() throws {
        let before = """
        # Doc

        First paragraph of the document.

        Second paragraph of the document.

        Third paragraph of the document.

        Fourth paragraph of the document.
        """
        let url = try writeFixture(name: "accent.md", contents: before)
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view), let gutter = gutterView(in: vc.view) else {
            return XCTFail("controller did not build its text view and gutter")
        }
        XCTAssertTrue(
            waitUntil { textView.string.contains("Fourth paragraph") },
            "initial render never completed"
        )
        XCTAssertTrue(gutter.accentBars.isEmpty, "nothing should be accented on first load")

        let after = before.replacingOccurrences(
            of: "Third paragraph of the document.",
            with: "Third paragraph, rewritten by the agent."
        )
        try after.write(to: url, atomically: false, encoding: .utf8)

        XCTAssertTrue(
            waitUntil { textView.string.contains("rewritten by the agent") },
            "the edit never rendered"
        )
        XCTAssertEqual(gutter.accentBars.count, 1, "exactly one block changed")

        guard let bar = gutter.accentBars.first,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else {
            return XCTFail("no accent bar to check")
        }
        let changedRange = (textView.string as NSString).range(of: "rewritten by the agent")
        let glyphRange = layoutManager.glyphRange(forCharacterRange: changedRange, actualCharacterRange: nil)
        let paragraphTop = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).minY
            + textView.textContainerInset.height

        XCTAssertEqual(
            bar.minY, paragraphTop, accuracy: 3,
            "the accent should sit beside the paragraph that changed"
        )
        XCTAssertLessThanOrEqual(
            bar.maxX, textView.textContainerInset.width,
            "the accent belongs in the gutter, not over the text"
        )
    }

    /// A write that does not change the content accents nothing — the reload
    /// still happens, but there is nothing to point at.
    func testReloadWithIdenticalContentAccentsNothing() throws {
        let source = "# Doc\n\nFirst paragraph.\n\nSecond paragraph.\n"
        let url = try writeFixture(name: "same.md", contents: source)
        let vc = makeController(for: url)
        guard let textView = textView(in: vc.view), let gutter = gutterView(in: vc.view) else {
            return XCTFail("controller did not build its text view and gutter")
        }
        XCTAssertTrue(
            waitUntil { textView.string.contains("Second paragraph") },
            "initial render never completed"
        )

        try source.write(to: url, atomically: false, encoding: .utf8)
        spinRunLoop(for: 0.6)

        XCTAssertTrue(
            gutter.accentBars.isEmpty,
            "an unchanged reload must not accent anything"
        )
    }
}
