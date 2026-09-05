import Foundation

/// A GUI app's own PATH comes from launchd and says nothing about what the
/// user's terminal will find, so the only honest way to answer "is
/// ~/.local/bin on your PATH?" is to ask the login shell.
enum LoginShellPath {

    private static let beginMarker = "MRKD-PATH:"

    /// Runs the user's login shell as an interactive login shell and reads its
    /// PATH. Returns nil if the shell could not be asked — the caller must say
    /// "unknown" rather than guess. Blocks, so call it off the main thread.
    static func read(timeout: TimeInterval = 4) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l -i so profile *and* rc files are read: PATH is set in .zshrc as
        // often as in .zprofile. The marker separates our answer from anything
        // a noisy startup file prints.
        process.arguments = ["-l", "-i", "-c", "printf '\\n\(beginMarker)%s' \"$PATH\""]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }

        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard process.terminationStatus == 0,
              let range = output.range(of: beginMarker, options: .backwards) else { return nil }

        let value = String(output[range.upperBound...])
        return value.isEmpty ? nil : value
    }
}
