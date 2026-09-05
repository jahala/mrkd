import XCTest
@testable import mrkd

/// Drives the real DispatchSource watcher with real filesystem operations.
/// The recorder below is not a mock of the thing under test — it is the
/// watcher's output channel, and every event it records was produced by an
/// actual write, rename, or unlink.
@MainActor
final class FileWatcherTests: XCTestCase {

    private final class Recorder: FileWatcherDelegate {
        var changes = 0
        var deletions = 0
        var onEvent: (() -> Void)?

        func fileWatcher(_ watcher: FileWatcher, didDetectChangeFor url: URL) {
            changes += 1
            onEvent?()
        }

        func fileWatcher(_ watcher: FileWatcher, didDetectDeletionOf url: URL) {
            deletions += 1
            onEvent?()
        }
    }

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testInPlaceWriteReportsAChange() throws {
        let url = tempDir.appendingPathComponent("a.md")
        try "one".write(to: url, atomically: false, encoding: .utf8)

        let recorder = Recorder()
        let watcher = FileWatcher(url: url)
        watcher.delegate = recorder
        watcher.start()
        defer { watcher.stop() }

        let event = expectation(description: "change reported")
        recorder.onEvent = { event.fulfill() }
        try "two".write(to: url, atomically: false, encoding: .utf8)

        wait(for: [event], timeout: 3)
        XCTAssertEqual(recorder.deletions, 0, "an in-place write is not a deletion")
        XCTAssertGreaterThanOrEqual(recorder.changes, 1)
    }

    /// An atomic save replaces the inode behind the path. The old file
    /// descriptor sees a delete, but the path is immediately valid again, so
    /// the watcher must report a change and keep watching the new inode.
    func testAtomicReplaceReportsAChangeNotADeletion() throws {
        let url = tempDir.appendingPathComponent("b.md")
        try "one".write(to: url, atomically: false, encoding: .utf8)

        let recorder = Recorder()
        let watcher = FileWatcher(url: url)
        watcher.delegate = recorder
        watcher.start()
        defer { watcher.stop() }

        let event = expectation(description: "change reported")
        recorder.onEvent = { event.fulfill() }
        try "two".write(to: url, atomically: true, encoding: .utf8)

        wait(for: [event], timeout: 3)
        XCTAssertEqual(recorder.deletions, 0, "an atomic save must not be reported as a deletion")
        XCTAssertGreaterThanOrEqual(recorder.changes, 1)

        // And the watcher must still be attached to the replacement file.
        recorder.changes = 0
        let second = expectation(description: "second change reported")
        recorder.onEvent = { second.fulfill() }
        try "three".write(to: url, atomically: true, encoding: .utf8)
        wait(for: [second], timeout: 3)
        XCTAssertGreaterThanOrEqual(recorder.changes, 1, "watch was not re-established after the replace")
        XCTAssertEqual(recorder.deletions, 0)
    }

    func testUnlinkReportsADeletion() throws {
        let url = tempDir.appendingPathComponent("c.md")
        try "one".write(to: url, atomically: false, encoding: .utf8)

        let recorder = Recorder()
        let watcher = FileWatcher(url: url)
        watcher.delegate = recorder
        watcher.start()
        defer { watcher.stop() }

        let event = expectation(description: "deletion reported")
        recorder.onEvent = { event.fulfill() }
        try FileManager.default.removeItem(at: url)

        wait(for: [event], timeout: 3)
        XCTAssertGreaterThanOrEqual(recorder.deletions, 1, "a real unlink must be reported as a deletion")
        XCTAssertEqual(recorder.changes, 0)
    }
}
