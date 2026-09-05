import XCTest
@testable import mrkd

/// `mrkd` with no arguments reopens the last document. The recent-documents
/// list outlives the files in it — agents move and delete markdown constantly —
/// so the selection is tested against files that really are, and really are
/// not, on disk.
final class RecentDocumentsTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-recents-tests-\(UUID().uuidString)")
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

    /// The real predicate the app uses, so these tests pin production behaviour
    /// rather than a stand-in written for the test.
    private let openable: (URL) -> Bool = { RecentDocuments.isOpenableFile($0) }

    func testTheMostRecentReadableDocumentIsChosen() throws {
        let newest = try makeFile("newest.md")
        let older = try makeFile("older.md")

        XCTAssertEqual(
            RecentDocuments.mostRecent(from: [newest, older], isOpenable: openable),
            newest
        )
    }

    func testDeletedDocumentsAreSkipped() throws {
        let deleted = try makeFile("gone.md")
        let survivor = try makeFile("still-here.md")
        try FileManager.default.removeItem(at: deleted)

        XCTAssertEqual(
            RecentDocuments.mostRecent(from: [deleted, survivor], isOpenable: openable),
            survivor
        )
    }

    func testNothingIsChosenWhenTheWholeListIsGone() throws {
        let deleted = try makeFile("gone.md")
        try FileManager.default.removeItem(at: deleted)

        XCTAssertNil(RecentDocuments.mostRecent(from: [deleted], isOpenable: openable))
        XCTAssertNil(RecentDocuments.mostRecent(from: [], isOpenable: openable))
    }

    func testDirectoriesInTheRecentListAreNotOffered() throws {
        let directory = tempDir.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = try makeFile("plan.md")

        XCTAssertEqual(
            RecentDocuments.mostRecent(from: [directory, file], isOpenable: openable),
            file
        )
    }
}
