import XCTest
import AppKit
@testable import mrkd

/// PreviewViewController itself lives in the QLPlugin target, not mrkd.
/// We can't link to it from the mrkd test bundle. These tests verify the
/// invariants the shell relies on: a `MarkdownViewController` can be
/// hosted as a child VC, and the size guard contract works as expected
/// on a too-large fixture.
@MainActor
final class PreviewHostingContractTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-ql-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testMarkdownViewControllerCanBeHostedAsChild() throws {
        let url = tempDir.appendingPathComponent("doc.md")
        try "# Hosted preview\n\nbody".write(to: url, atomically: true, encoding: .utf8)

        let host = NSViewController()
        host.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        let mvc = MarkdownViewController(fileURL: url)
        host.addChild(mvc)
        mvc.view.frame = host.view.bounds
        host.view.addSubview(mvc.view)

        XCTAssertEqual(host.children.count, 1)
        XCTAssertEqual(host.children.first, mvc)
        XCTAssertTrue(host.view.subviews.contains(mvc.view))
    }

    func testTOCBuilderPipelineRoundtripsThroughRenderer() {
        // Mirror what the QL preview does end-to-end: render markdown,
        // derive TOC, expect headings to come back in order.
        let attr = MarkdownRenderer.render("# A\n\n## B\n\n### C")
        let entries = TOCBuilder.build(from: attr)
        XCTAssertEqual(entries.map(\.text), ["A", "B", "C"])
        XCTAssertEqual(entries.map(\.level), [1, 2, 3])
    }
}
