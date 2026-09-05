import XCTest
@testable import mrkd

/// Exercises the pure argument parser against a real temporary directory —
/// real files, a real directory, real relative-path resolution — so the
/// filesystem answers are the ones the shipping binary will get.
final class CLIArgumentParserTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String, contents: String = "# doc\n") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func parse(
        _ arguments: [String],
        standardInput: StandardInputKind = .terminal
    ) -> CLIInvocation {
        CLIArgumentParser.parse(
            arguments: arguments,
            standardInput: standardInput,
            workingDirectory: tempDir,
            pathKind: { PathKind.of($0) }
        )
    }

    // MARK: - Files

    func testAbsoluteFilePathOpensThatFile() throws {
        let file = try makeFile("plan.md")
        guard case .openFile(let url) = parse([file.path]) else {
            return XCTFail("expected .openFile, got \(parse([file.path]))")
        }
        XCTAssertEqual(url.path, file.path)
    }

    func testRelativePathIsResolvedAgainstTheWorkingDirectory() throws {
        _ = try makeFile("notes/plan.md")
        guard case .openFile(let url) = parse(["notes/../notes/plan.md"]) else {
            return XCTFail("expected .openFile for a relative path")
        }
        XCTAssertEqual(url.path, tempDir.appendingPathComponent("notes/plan.md").path)
        XCTAssertFalse(url.path.contains(".."), "relative segments must be normalised away")
    }

    func testRelativePathResolvesThroughASymlinkedWorkingDirectory() throws {
        // A shell's working directory is often reached through a symlink —
        // /tmp is one, and so is any symlinked project folder. Foundation only
        // stats the base path to decide whether it is a directory, and that
        // check does not see through the link: without an explicit
        // isDirectory: true the base loses its last component and "plan.md"
        // resolves into the *parent* directory. That is the difference this
        // test exists to catch.
        let real = tempDir.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "# doc\n".write(to: real.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)

        let linked = tempDir.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: real)

        let invocation = CLIArgumentParser.parse(
            arguments: ["plan.md"],
            standardInput: .terminal,
            workingDirectory: linked,
            pathKind: { PathKind.of($0) }
        )

        guard case .openFile(let url) = invocation else {
            return XCTFail("expected .openFile inside the symlinked working directory, got \(invocation)")
        }
        XCTAssertEqual(url.path, linked.appendingPathComponent("plan.md").path)
    }

    func testNonexistentFileFailsAndNamesThePathAsTyped() {
        guard case .failed(let failure) = parse(["missing.md"]) else {
            return XCTFail("expected .failed for a nonexistent file")
        }
        XCTAssertEqual(failure, .noSuchFile("missing.md"))
        XCTAssertTrue(failure.message.contains("missing.md"), failure.message)
    }

    // MARK: - Directories are out of scope, and must say so

    func testDirectoryArgumentFailsWithAnExplicitMessage() throws {
        let directory = tempDir.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard case .failed(let failure) = parse([directory.path]) else {
            return XCTFail("expected .failed for a directory")
        }
        XCTAssertEqual(failure, .isDirectory(directory.path))
        XCTAssertTrue(failure.message.lowercased().contains("directory"), failure.message)
    }

    func testWorkingDirectoryItselfIsRejected() {
        guard case .failed(.isDirectory) = parse(["."]) else {
            return XCTFail("expected \".\" to be rejected as a directory")
        }
    }

    // MARK: - Standard input

    func testDashReadsStandardInput() {
        XCTAssertEqual(parse(["-"]), .renderStandardInput)
    }

    func testNoArgumentsWithPipedStandardInputReadsStandardInput() {
        XCTAssertEqual(parse([], standardInput: .piped), .renderStandardInput)
    }

    func testNoArgumentsAtATerminalRestoresTheLastDocument() {
        XCTAssertEqual(parse([], standardInput: .terminal), .restoreLastDocument)
    }

    func testNoArgumentsWithoutStandardInputRestoresTheLastDocument() {
        XCTAssertEqual(parse([], standardInput: .absent), .restoreLastDocument)
    }

    func testExplicitFileWinsOverPipedStandardInput() throws {
        let file = try makeFile("plan.md")
        guard case .openFile = parse([file.path], standardInput: .piped) else {
            return XCTFail("a named file must take precedence over piped input")
        }
    }

    // MARK: - Arity and help

    func testTwoArgumentsFail() throws {
        let first = try makeFile("a.md")
        let second = try makeFile("b.md")
        guard case .failed(let failure) = parse([first.path, second.path]) else {
            return XCTFail("expected .failed for two file arguments")
        }
        XCTAssertEqual(failure, .tooManyArguments(count: 2))
    }

    func testHelpFlagsShowUsage() {
        XCTAssertEqual(parse(["-h"]), .showUsage)
        XCTAssertEqual(parse(["--help"]), .showUsage)
        XCTAssertTrue(CLIArgumentParser.usage.contains("mrkd"))
    }

    // MARK: - PathKind against the real filesystem

    func testPathKindDistinguishesFileDirectoryAndMissing() throws {
        let file = try makeFile("real.md")
        let directory = tempDir.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertEqual(PathKind.of(file), .file)
        XCTAssertEqual(PathKind.of(directory), .directory)
        XCTAssertEqual(PathKind.of(tempDir.appendingPathComponent("nope.md")), .missing)
    }

    // MARK: - Standard input detection against real file descriptors

    func testDetectTreatsARealPipeAsPipedInput() throws {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        defer { close(fds[0]); close(fds[1]) }
        XCTAssertEqual(StandardInputKind.detect(fileDescriptor: fds[0]), .piped)
    }

    func testDetectTreatsARedirectedFileAsPipedInput() throws {
        let file = try makeFile("input.md")
        let fd = open(file.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(StandardInputKind.detect(fileDescriptor: fd), .piped)
    }

    func testDetectTreatsDevNullAsAbsent() {
        // This is what LaunchServices hands a GUI app; misreading it as piped
        // input would make every double-click try to render an empty document.
        let fd = open("/dev/null", O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(StandardInputKind.detect(fileDescriptor: fd), .absent)
    }

    func testDetectTreatsATerminalAsTerminal() throws {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        try XCTSkipIf(master < 0, "no pseudo-terminal available in this environment")
        defer { close(master) }
        XCTAssertEqual(StandardInputKind.detect(fileDescriptor: master), .terminal)
    }
}
