import XCTest
import AppKit
@testable import mrkd

/// Mermaid in a live document: a real file on disk, a real controller in a
/// real (offscreen) window, real merman bitmaps. This is where the feature
/// meets the things that landed before it — live reload, find in page, the
/// changed-block accents, and math on the same seam.
@MainActor
final class MermaidIntegrationTests: XCTestCase {

    private var tempDir: URL!
    private var windows: [NSWindow] = []

    private static let flowchart = """
        ```mermaid
        flowchart TD
          A[Read the file] --> B{Is it markdown?}
          B -->|yes| C[Render]
          B -->|no| D[Open elsewhere]
        ```
        """

    override func setUp() async throws {
        _ = NSApplication.shared
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-mermaid-\(UUID().uuidString)")
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

    @discardableResult
    private func waitUntil(timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
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

    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }

    private func diagramAttachments(in textView: NSTextView) -> [NSTextAttachment] {
        guard let storage = textView.textStorage else { return [] }
        return DeferredAttachment.all(in: storage).compactMap { entry in
            guard entry.attachment.kind == .diagram else { return nil }
            return storage.attribute(
                .attachment, at: entry.range.location, effectiveRange: nil
            ) as? NSTextAttachment
        }
    }

    /// True once the first diagram has been given a bitmap wider than the
    /// 300pt placeholder the renderer leaves behind.
    private func resolvedDiagram(in textView: NSTextView) -> NSTextAttachment? {
        diagramAttachments(in: textView).first { $0.bounds.width > 0 }
    }

    // MARK: - Rendering

    func testADiagramInADocumentIsRasterisedIntoItsAttachment() throws {
        let url = try writeFixture(
            name: "diagram.md",
            contents: "# Flow\n\n\(Self.flowchart)\n"
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))

        XCTAssertTrue(
            waitUntil { self.resolvedDiagram(in: textView) != nil },
            "the diagram never got its bitmap"
        )
        let attachment = try XCTUnwrap(resolvedDiagram(in: textView))
        let image = try XCTUnwrap(attachment.image)

        XCTAssertGreaterThan(image.size.width, 100)
        XCTAssertGreaterThan(image.size.height, 100)
        XCTAssertEqual(attachment.bounds.width, image.size.width, accuracy: 0.5)
        XCTAssertEqual(attachment.bounds.height, image.size.height, accuracy: 0.5)
    }

    func testADiagramWiderThanTheColumnIsScaledDownToFit() throws {
        let url = try writeFixture(
            name: "wide.md",
            contents: """
                # Wide

                ```mermaid
                flowchart LR
                  A[A really quite long node label here] --> B[Another long one]
                  B --> C[And a third long label to push it out]
                  C --> D[Plus a fourth for good measure indeed]
                ```
                """
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { self.resolvedDiagram(in: textView) != nil })

        let attachment = try XCTUnwrap(resolvedDiagram(in: textView))
        let containerWidth = try XCTUnwrap(textView.textContainer?.containerSize.width)

        XCTAssertLessThanOrEqual(
            attachment.bounds.width, containerWidth,
            "the diagram is wider than the column it sits in"
        )
        // Scaled, not squashed.
        let image = try XCTUnwrap(attachment.image)
        XCTAssertEqual(
            attachment.bounds.width / attachment.bounds.height,
            image.size.width / image.size.height,
            accuracy: 0.01
        )
    }

    func testSeveralDiagramsInOneDocumentAllResolve() throws {
        let url = try writeFixture(
            name: "many.md",
            contents: """
                # Many

                \(Self.flowchart)

                Some prose between them.

                ```mermaid
                sequenceDiagram
                  participant U as User
                  U->>M: open plan.md
                ```
                """
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))

        XCTAssertTrue(
            waitUntil { self.diagramAttachments(in: textView).allSatisfy { $0.bounds.width > 0 }
                && self.diagramAttachments(in: textView).count == 2 },
            "not every diagram resolved"
        )
    }

    // MARK: - The fallback

    /// A broken diagram must show the reader their own source. A blank space
    /// in the middle of a document is the worst possible outcome: nothing to
    /// read and nothing to fix.
    func testABrokenDiagramIsReplacedByItsSourceInTheDocument() throws {
        let url = try writeFixture(
            name: "broken.md",
            contents: """
                # Broken

                ```mermaid
                flowchart TD
                  A[Unclosed --> B{{{
                ```
                """
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))

        XCTAssertTrue(
            waitUntil { textView.textStorage?.string.contains("A[Unclosed") ?? false },
            "the broken diagram left a gap instead of its source"
        )
        // And no diagram attachment is left hanging around waiting.
        XCTAssertTrue(diagramAttachments(in: textView).isEmpty)
    }

    func testAGoodDiagramBesideABrokenOneStillRenders() throws {
        let url = try writeFixture(
            name: "mixed.md",
            contents: """
                # Mixed

                ```mermaid
                flowchart TD
                  A[Unclosed --> B{{{
                ```

                \(Self.flowchart)
                """
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))

        XCTAssertTrue(
            waitUntil {
                (textView.textStorage?.string.contains("A[Unclosed") ?? false)
                    && self.resolvedDiagram(in: textView) != nil
            },
            "replacing the broken diagram lost the good one"
        )
    }

    /// The accents that mark what an agent just changed map rendered text
    /// back to source blocks. The fallback replaces text in place, so it has
    /// to carry that tag across or the block stops being highlightable.
    func testTheFallbackKeepsItsSourceBlockTagInTheLiveDocument() throws {
        let url = try writeFixture(
            name: "tagged.md",
            contents: """
                # Tagged

                A paragraph.

                ```mermaid
                flowchart TD
                  A[Unclosed --> B{{{
                ```
                """
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { textView.textStorage?.string.contains("A[Unclosed") ?? false })

        let storage = try XCTUnwrap(textView.textStorage)
        let location = (storage.string as NSString).range(of: "A[Unclosed").location
        XCTAssertNotEqual(location, NSNotFound)
        XCTAssertEqual(
            storage.attribute(.sourceBlockIndex, at: location, effectiveRange: nil) as? Int,
            2,
            "the fallback lost the block it came from"
        )
    }

    // MARK: - Living with the rest of the app

    func testMathAndDiagramsInOneDocumentBothResolve() throws {
        let url = try writeFixture(
            name: "both.md",
            contents: """
                # Both

                Einstein wrote $E = mc^2$ on a board.

                \(Self.flowchart)
                """
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))

        XCTAssertTrue(
            waitUntil {
                guard let storage = textView.textStorage else { return false }
                let entries = DeferredAttachment.all(in: storage)
                guard entries.count == 2 else { return false }
                return entries.allSatisfy { entry in
                    let attachment = storage.attribute(
                        .attachment, at: entry.range.location, effectiveRange: nil
                    ) as? NSTextAttachment
                    return (attachment?.bounds.width ?? 0) > 0
                }
            },
            "math and a diagram could not both resolve on the shared seam"
        )
    }

    /// Find in page walks the text storage. A diagram occupies one attachment
    /// character, so text on either side of it must still be findable — and
    /// the fallback path rewrites the storage, which is where offsets go bad.
    func testTextAfterABrokenDiagramIsStillFindable() throws {
        let url = try writeFixture(
            name: "find.md",
            contents: """
                # Find

                ```mermaid
                flowchart TD
                  A[Unclosed --> B{{{
                ```

                A distinctive sentence after the diagram.
                """
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { textView.textStorage?.string.contains("A[Unclosed") ?? false })

        let storage = try XCTUnwrap(textView.textStorage)
        let found = (storage.string as NSString).range(of: "A distinctive sentence")
        XCTAssertNotEqual(found.location, NSNotFound)
        XCTAssertLessThanOrEqual(NSMaxRange(found), storage.length)
    }

    func testALiveReloadThatChangesADiagramRendersTheNewOne() throws {
        let url = try writeFixture(name: "reload.md", contents: "# Reload\n\n\(Self.flowchart)\n")
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { self.resolvedDiagram(in: textView) != nil })
        let before = try XCTUnwrap(resolvedDiagram(in: textView)?.image)

        try """
            # Reload

            ```mermaid
            flowchart TD
              A[Read the file] --> B{Is it markdown?}
              B -->|yes| C[Render]
              B -->|no| D[Open elsewhere]
              D --> E[A brand new node that changes the layout]
            ```
            """.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertTrue(
            waitUntil {
                guard let now = self.resolvedDiagram(in: textView)?.image else { return false }
                return now !== before
            },
            "the edited diagram never re-rendered"
        )
    }
}
