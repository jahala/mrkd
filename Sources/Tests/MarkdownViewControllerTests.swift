import XCTest
import AppKit
@testable import mrkd

@MainActor
final class MarkdownViewControllerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeFixture(name: String, contents: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testInitWithFileURLDoesNotCrash() throws {
        let url = try writeFixture(name: "test.md", contents: "# Hello\n\nbody")
        let vc = MarkdownViewController(fileURL: url)
        XCTAssertNotNil(vc)
        XCTAssertEqual(vc.fileURL, url)
    }

    func testLoadViewBuildsViewHierarchy() throws {
        let url = try writeFixture(name: "test.md", contents: "# Title")
        let vc = MarkdownViewController(fileURL: url)
        _ = vc.view  // forces loadView()
        XCTAssertNotNil(vc.view)
    }

    func testViewDidLoadDoesNotCrash() throws {
        let url = try writeFixture(name: "test.md", contents: "# Title\n\nSome text.")
        let vc = MarkdownViewController(fileURL: url)
        vc.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        vc.viewDidLoad()
        // The render is async; this just verifies the controller can be
        // brought up without throwing or crashing.
        XCTAssertNotNil(vc.view)
    }
}
