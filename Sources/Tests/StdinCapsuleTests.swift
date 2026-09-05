import XCTest
@testable import mrkd

/// The capsule is how a piped document travels from the `mrkd` command to the
/// running app: the CLI writes the piped bytes into one known directory, and
/// the app recognises files from that directory as source-without-a-file
/// rather than as documents on disk. Both halves are tested against a real
/// directory tree because the recognition rule is a path comparison.
final class StdinCapsuleTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-capsule-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testCapsuleDirectoryLivesUnderTheAppsCachesFolder() {
        XCTAssertEqual(
            StdinCapsule.directory(homeDirectory: home).path,
            home.appendingPathComponent("Library/Caches/com.mrkd.app/stdin").path
        )
    }

    func testAFileWrittenIntoTheCapsuleDirectoryIsRecognised() throws {
        let directory = StdinCapsule.directory(homeDirectory: home)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let capsule = StdinCapsule.fileURL(homeDirectory: home, identifier: "abc123")
        try "# piped\n".write(to: capsule, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: capsule.path))
        XCTAssertTrue(StdinCapsule.isCapsule(capsule, homeDirectory: home))
    }

    func testAnOrdinaryDocumentIsNotACapsule() throws {
        let document = home.appendingPathComponent("plan.md")
        try "# plan\n".write(to: document, atomically: true, encoding: .utf8)

        XCTAssertFalse(StdinCapsule.isCapsule(document, homeDirectory: home))
    }

    func testASimilarlyNamedFileElsewhereIsNotACapsule() throws {
        let decoy = home.appendingPathComponent("stdin/abc123.md")
        try FileManager.default.createDirectory(
            at: decoy.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# decoy\n".write(to: decoy, atomically: true, encoding: .utf8)

        XCTAssertFalse(StdinCapsule.isCapsule(decoy, homeDirectory: home))
    }

    func testCapsuleFilesAreMarkdownAndUniquePerInvocation() {
        let first = StdinCapsule.fileURL(homeDirectory: home, identifier: "one")
        let second = StdinCapsule.fileURL(homeDirectory: home, identifier: "two")

        XCTAssertEqual(first.pathExtension, "md")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), second.deletingLastPathComponent())
    }
}
