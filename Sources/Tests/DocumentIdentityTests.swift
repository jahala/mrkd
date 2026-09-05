import XCTest
@testable import mrkd

/// Two invocations of `mrkd` must land on one window, and the paths a shell
/// hands over are rarely spelled identically — `./plan.md`, `dir/../plan.md`,
/// a symlink, `/tmp` versus `/private/tmp`. The identity key is what collapses
/// them, so it is tested against real files and a real symlink.
final class DocumentIdentityTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-identity-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "# doc\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testDotSegmentsCollapseToOneIdentity() throws {
        let file = try makeFile("plan.md")
        let roundabout = tempDir.appendingPathComponent("sub/../plan.md")

        XCTAssertEqual(DocumentIdentity.key(for: file), DocumentIdentity.key(for: roundabout))
    }

    func testASymlinkAndItsTargetShareOneIdentity() throws {
        let file = try makeFile("plan.md")
        let link = tempDir.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertEqual(DocumentIdentity.key(for: link), DocumentIdentity.key(for: file))
    }

    func testASymlinkedParentDirectoryResolvesToTheSameIdentity() throws {
        let real = tempDir.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let file = real.appendingPathComponent("plan.md")
        try "# doc\n".write(to: file, atomically: true, encoding: .utf8)

        let linkedDir = tempDir.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: linkedDir, withDestinationURL: real)

        XCTAssertEqual(
            DocumentIdentity.key(for: linkedDir.appendingPathComponent("plan.md")),
            DocumentIdentity.key(for: file)
        )
    }

    func testDifferentFilesKeepDifferentIdentities() throws {
        let first = try makeFile("a.md")
        let second = try makeFile("b.md")

        XCTAssertNotEqual(DocumentIdentity.key(for: first), DocumentIdentity.key(for: second))
    }

    func testIdentityIsStableForAFileThatDoesNotExistYet() {
        let ghost = tempDir.appendingPathComponent("later.md")

        XCTAssertEqual(DocumentIdentity.key(for: ghost), DocumentIdentity.key(for: ghost))
        XCTAssertTrue(DocumentIdentity.key(for: ghost).hasSuffix("later.md"))
    }
}
