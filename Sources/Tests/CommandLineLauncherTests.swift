import XCTest
@testable import mrkd

/// The launcher is a shell script, so it is tested the way a shell script has
/// to be tested: generated, written to a real directory, syntax-checked by
/// /bin/sh, and then actually executed against a stand-in executable that
/// reports the arguments it received.
final class CommandLineLauncherTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-launcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    /// Writes an executable stand-in for the app binary that prints the
    /// arguments it was handed, one per line.
    private func makeArgumentEchoingBinary(named name: String = "mrkd") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "#!/bin/sh\nfor a in \"$@\"; do echo \"$a\"; done\n"
            .write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    private func run(_ executable: URL, _ arguments: [String] = []) throws -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self)
        )
    }

    private func writeLauncher(forAppBinary binary: URL) throws -> URL {
        let script = CommandLineLauncher.script(appExecutable: binary)
        let url = tempDir.appendingPathComponent("bin/mrkd")
        let decision = try LauncherInstallation.install(script: script, at: url)
        XCTAssertEqual(decision, .write)
        return url
    }

    // MARK: - Script contract

    func testGeneratedScriptIsValidShellEvenWhenThePathContainsAQuote() throws {
        let awkward = URL(fileURLWithPath: "/Users/jan/Jan's Apps/mrkd.app/Contents/MacOS/mrkd")
        let script = CommandLineLauncher.script(appExecutable: awkward)
        let url = tempDir.appendingPathComponent("quoted-launcher")
        try script.write(to: url, atomically: true, encoding: .utf8)

        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/bin/sh")
        check.arguments = ["-n", url.path]
        try check.run()
        check.waitUntilExit()
        XCTAssertEqual(check.terminationStatus, 0, "generated script is not valid /bin/sh:\n\(script)")
    }

    func testScriptIsIdenticalWhicheverPathTheAppWasReachedBy() throws {
        // Bundle.main.executableURL reports the route the process was launched
        // by: /tmp/… from a shell, /private/tmp/… from LaunchServices. If that
        // leaked into the script, an installed command would look outdated on
        // every visit to Settings and be rewritten each time.
        let real = tempDir.appendingPathComponent("real/mrkd.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let executable = real.appendingPathComponent("mrkd")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)

        let alias = tempDir.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: tempDir.appendingPathComponent("real")
        )
        let viaAlias = alias.appendingPathComponent("mrkd.app/Contents/MacOS/mrkd")

        XCTAssertEqual(
            CommandLineLauncher.script(appExecutable: viaAlias),
            CommandLineLauncher.script(appExecutable: executable)
        )
    }

    func testLauncherForwardsArgumentsToTheAppBinaryBehindTheCLISentinel() throws {
        let binary = try makeArgumentEchoingBinary()
        let launcher = try writeLauncher(forAppBinary: binary)

        let result = try run(launcher, ["some file.md"])

        XCTAssertEqual(result.status, 0, result.err)
        XCTAssertEqual(
            result.out,
            "\(CommandLineLauncher.sentinel)\nsome file.md\n",
            "the launcher must pass the CLI sentinel plus the user's arguments, unsplit"
        )
    }

    func testLauncherWithNoArgumentsStillSignalsCLIMode() throws {
        let binary = try makeArgumentEchoingBinary()
        let launcher = try writeLauncher(forAppBinary: binary)

        let result = try run(launcher)

        XCTAssertEqual(result.status, 0, result.err)
        XCTAssertEqual(result.out, "\(CommandLineLauncher.sentinel)\n")
    }

    func testLauncherReportsAMissingAppInsteadOfFailingSilently() throws {
        let launcher = try writeLauncher(
            forAppBinary: tempDir.appendingPathComponent("gone.app/Contents/MacOS/mrkd")
        )

        let result = try run(launcher, ["plan.md"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.err.contains("mrkd"), result.err)
        XCTAssertTrue(result.out.isEmpty)
    }

    // MARK: - Installation against a real directory

    func testInstallWritesAnExecutableLauncherAndCreatesMissingDirectories() throws {
        let binary = try makeArgumentEchoingBinary()
        let script = CommandLineLauncher.script(appExecutable: binary)
        let destination = tempDir.appendingPathComponent("nested/.local/bin/mrkd")

        let decision = try LauncherInstallation.install(script: script, at: destination)

        XCTAssertEqual(decision, .write)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), script)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: destination.path))
    }

    func testReinstallingTheSameLauncherIsIdempotent() throws {
        let binary = try makeArgumentEchoingBinary()
        let script = CommandLineLauncher.script(appExecutable: binary)
        let destination = tempDir.appendingPathComponent("bin/mrkd")

        XCTAssertEqual(try LauncherInstallation.install(script: script, at: destination), .write)
        let firstInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int

        XCTAssertEqual(try LauncherInstallation.install(script: script, at: destination), .alreadyInstalled)

        let secondInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int
        XCTAssertEqual(firstInode, secondInode, "an unchanged launcher must not be rewritten")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), script)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: destination.path))
    }

    func testInstallRepairsAnUnexecutableLauncher() throws {
        let binary = try makeArgumentEchoingBinary()
        let script = CommandLineLauncher.script(appExecutable: binary)
        let destination = tempDir.appendingPathComponent("bin/mrkd")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try script.write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)

        XCTAssertEqual(try LauncherInstallation.install(script: script, at: destination), .alreadyInstalled)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: destination.path))
    }

    func testInstallReplacesALauncherPointingAtAnOlderCopyOfTheApp() throws {
        let destination = tempDir.appendingPathComponent("bin/mrkd")
        let stale = CommandLineLauncher.script(appExecutable: URL(fileURLWithPath: "/Volumes/Old/mrkd.app/Contents/MacOS/mrkd"))
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try stale.write(to: destination, atomically: true, encoding: .utf8)

        let current = CommandLineLauncher.script(appExecutable: URL(fileURLWithPath: "/Applications/mrkd.app/Contents/MacOS/mrkd"))
        XCTAssertEqual(try LauncherInstallation.install(script: current, at: destination), .write)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), current)
    }

    func testInstallRefusesToOverwriteAFileItDidNotWrite() throws {
        let destination = tempDir.appendingPathComponent("bin/mrkd")
        let foreign = "#!/bin/sh\necho \"someone else's tool\"\n"
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try foreign.write(to: destination, atomically: true, encoding: .utf8)

        let script = CommandLineLauncher.script(appExecutable: URL(fileURLWithPath: "/Applications/mrkd.app/Contents/MacOS/mrkd"))
        XCTAssertEqual(try LauncherInstallation.install(script: script, at: destination), .refused)
        XCTAssertEqual(
            try String(contentsOf: destination, encoding: .utf8),
            foreign,
            "an unrelated file must be left exactly as it was"
        )
    }

    func testInstallRefusesWhenTheDestinationIsADirectory() throws {
        let destination = tempDir.appendingPathComponent("bin/mrkd")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let script = CommandLineLauncher.script(appExecutable: URL(fileURLWithPath: "/Applications/mrkd.app/Contents/MacOS/mrkd"))
        XCTAssertEqual(try LauncherInstallation.install(script: script, at: destination), .refused)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testExistingEntryReadsBackWhatIsActuallyOnDisk() throws {
        let missing = tempDir.appendingPathComponent("bin/mrkd")
        XCTAssertEqual(LauncherInstallation.existingEntry(at: missing), .none)

        let script = CommandLineLauncher.script(appExecutable: URL(fileURLWithPath: "/Applications/mrkd.app/Contents/MacOS/mrkd"))
        try FileManager.default.createDirectory(
            at: missing.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try script.write(to: missing, atomically: true, encoding: .utf8)
        XCTAssertEqual(LauncherInstallation.existingEntry(at: missing), .text(script))

        let binary = tempDir.appendingPathComponent("bin/binary")
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: binary)
        XCTAssertEqual(LauncherInstallation.existingEntry(at: binary), .opaque)
    }

    // MARK: - Install destination

    func testInstallDestinationIsLocalBinUnderTheUsersHome() {
        let home = URL(fileURLWithPath: "/Users/jan")
        XCTAssertEqual(
            CommandLineLauncher.installURL(homeDirectory: home).path,
            "/Users/jan/.local/bin/mrkd"
        )
    }

    func testDisplayPathAbbreviatesTheHomeDirectory() {
        let home = URL(fileURLWithPath: "/Users/jan")
        XCTAssertEqual(
            CommandLineLauncher.displayPath(
                CommandLineLauncher.installURL(homeDirectory: home),
                homeDirectory: home
            ),
            "~/.local/bin/mrkd"
        )
        XCTAssertEqual(
            CommandLineLauncher.displayPath(URL(fileURLWithPath: "/usr/local/bin/mrkd"), homeDirectory: home),
            "/usr/local/bin/mrkd"
        )
    }

    // MARK: - PATH membership

    func testPathMembershipRecognisesTheDirectoryInAllItsWrittenForms() {
        let home = URL(fileURLWithPath: "/Users/jan")
        let directory = URL(fileURLWithPath: "/Users/jan/.local/bin")

        XCTAssertTrue(ShellPath.contains(directory, in: "/usr/bin:/Users/jan/.local/bin:/bin", homeDirectory: home))
        XCTAssertTrue(ShellPath.contains(directory, in: "~/.local/bin:/usr/bin", homeDirectory: home))
        XCTAssertTrue(ShellPath.contains(directory, in: "/usr/bin:/Users/jan/.local/bin/", homeDirectory: home))
        XCTAssertTrue(ShellPath.contains(directory, in: "/Users/jan/.local/../.local/bin", homeDirectory: home))
    }

    func testPathMembershipRejectsUnrelatedAndPartialEntries() {
        let home = URL(fileURLWithPath: "/Users/jan")
        let directory = URL(fileURLWithPath: "/Users/jan/.local/bin")

        XCTAssertFalse(ShellPath.contains(directory, in: "/usr/bin:/bin:/usr/sbin:/sbin", homeDirectory: home))
        XCTAssertFalse(ShellPath.contains(directory, in: "", homeDirectory: home))
        XCTAssertFalse(ShellPath.contains(directory, in: "::", homeDirectory: home))
        XCTAssertFalse(ShellPath.contains(directory, in: "/Users/jan/.local/binaries", homeDirectory: home))
        XCTAssertFalse(ShellPath.contains(directory, in: "/Users/other/.local/bin", homeDirectory: home))
    }

    // MARK: - What Settings tells the user

    func testStatusReflectsWhatIsOnDisk() {
        let script = CommandLineLauncher.script(appExecutable: URL(fileURLWithPath: "/Applications/mrkd.app/Contents/MacOS/mrkd"))
        let stale = CommandLineLauncher.script(appExecutable: URL(fileURLWithPath: "/Volumes/Old/mrkd.app/Contents/MacOS/mrkd"))

        XCTAssertEqual(LauncherInstaller.status(existing: .none, desired: script), .notInstalled)
        XCTAssertEqual(LauncherInstaller.status(existing: .text(script), desired: script), .installed)
        XCTAssertEqual(LauncherInstaller.status(existing: .text(stale), desired: script), .outdated)
        XCTAssertEqual(LauncherInstaller.status(existing: .text("#!/bin/sh\necho hi\n"), desired: script), .occupied)
        XCTAssertEqual(LauncherInstaller.status(existing: .opaque, desired: script), .occupied)
    }

    func testStatusTextTellsTheUserPlainlyWhenTheDirectoryIsNotOnPath() {
        let text = LauncherInstaller.statusText(
            status: .installed,
            displayPath: "~/.local/bin/mrkd",
            pathState: .missing
        )
        XCTAssertTrue(text.contains("~/.local/bin"), text)
        XCTAssertTrue(text.contains("PATH"), text)
        XCTAssertTrue(text.contains("export PATH="), "the user needs the exact line to add: \(text)")
    }

    func testStatusTextStaysQuietAboutPathWhenTheDirectoryIsOnIt() {
        let text = LauncherInstaller.statusText(
            status: .installed,
            displayPath: "~/.local/bin/mrkd",
            pathState: .onPath
        )
        XCTAssertTrue(text.contains("~/.local/bin/mrkd"), text)
        XCTAssertFalse(text.contains("export PATH="), text)
    }

    func testStatusTextAdmitsWhenTheShellPathCouldNotBeRead() {
        let text = LauncherInstaller.statusText(
            status: .installed,
            displayPath: "~/.local/bin/mrkd",
            pathState: .unknown
        )
        XCTAssertTrue(text.contains("~/.local/bin"), text)
        XCTAssertFalse(text.contains("export PATH="), text)
    }

    func testStatusTextForAnOccupiedPathRefusesRatherThanPromises() {
        let text = LauncherInstaller.statusText(
            status: .occupied,
            displayPath: "~/.local/bin/mrkd",
            pathState: .onPath
        )
        XCTAssertTrue(text.contains("~/.local/bin/mrkd"), text)
        XCTAssertTrue(text.lowercased().contains("another file"), text)
    }
}
