import Foundation

/// The command-line half of the app binary. It never becomes an NSApplication:
/// it resolves the arguments to one decision, hands that to LaunchServices —
/// which routes it to the already-running instance if there is one — and exits.
enum CLIEntryPoint {

    /// True when this process was started by the installed `mrkd` launcher.
    static func shouldHandle(arguments: [String]) -> Bool {
        arguments.count > 1 && arguments[1] == CommandLineLauncher.sentinel
    }

    static func run(arguments: [String]) -> Int32 {
        let invocation = CLIArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2)),
            standardInput: StandardInputKind.detect(fileDescriptor: STDIN_FILENO),
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            pathKind: { PathKind.of($0) }
        )

        switch invocation {
        case .showUsage:
            print(CLIArgumentParser.usage)
            return 0

        case .failed(let failure):
            report(failure.message)
            return 1

        case .openFile(let url):
            return activateApp(opening: [url])

        case .restoreLastDocument:
            return activateApp(opening: [])

        case .renderStandardInput:
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard !data.isEmpty else {
                report("mrkd: nothing arrived on standard input")
                return 1
            }
            do {
                return activateApp(opening: [try stageStandardInput(data)])
            } catch {
                report("mrkd: could not stage piped input: \(error.localizedDescription)")
                return 1
            }
        }
    }

    // MARK: - Edges

    /// Parks piped bytes where the app knows to look for source without a file.
    private static func stageStandardInput(_ data: Data) throws -> URL {
        let url = StdinCapsule.fileURL(
            homeDirectory: URL(fileURLWithPath: NSHomeDirectory()),
            identifier: UUID().uuidString
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    /// `open -a` on this very bundle: a running instance is reused and brought
    /// forward, a cold one is launched, and either way the URLs arrive through
    /// the app's existing file-opening path.
    private static func activateApp(opening urls: [URL]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", Bundle.main.bundleURL.path] + urls.map(\.path)

        do {
            try process.run()
        } catch {
            report("mrkd: could not launch mrkd.app: \(error.localizedDescription)")
            return 1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
