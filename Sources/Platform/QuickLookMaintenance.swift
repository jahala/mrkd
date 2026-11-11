import Foundation

/// The process half of the Quick Look check: run the commands `QuickLookCheck`
/// chooses and hand their output back to it. Nothing here decides policy.
/// Every function blocks, so call them off the main thread.
enum QuickLookMaintenance {

    /// Runs `pluginkit -m` (read-only) and reports what it says about this copy.
    static func check(appURL: URL) -> QuickLookReport {
        let appPath = appURL.path
        let outsideApplications = QuickLookCheck.isOutsideApplications(appPath: appPath)

        let appex = QuickLookCheck.appexPath(appPath: appPath)
        guard FileManager.default.fileExists(atPath: appex) else {
            // A build without the extension, such as `swift run`.
            return QuickLookReport(
                registration: .couldNotCheck("This copy of mrkd has no Quick Look extension at \(appex)."),
                outsideApplications: outsideApplications
            )
        }

        return QuickLookCheck.report(listOutcome: run(QuickLookCheck.listStep), appPath: appPath)
    }

    /// Runs the steps in order and stops at the first that fails. Returns that
    /// failure in words, or nil when every step succeeded.
    static func perform(_ steps: [QuickLookStep]) -> String? {
        for step in steps {
            if let failure = QuickLookCheck.failure(of: step, run(step)) {
                return failure
            }
        }
        return nil
    }

    /// Runs one command and collects what it printed. A command that does
    /// not finish within `timeout` is stopped and reported as such, so a
    /// wedged daemon cannot leave the check waiting for ever.
    static func run(_ step: QuickLookStep, timeout: TimeInterval = 20) -> QuickLookCommandOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: step.executable)
        process.arguments = step.arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return .couldNotStart(error.localizedDescription)
        }

        // Drain both pipes while the command runs, so a chatty command can
        // never fill a pipe and stall.
        let collected = CollectedOutput()
        let reader = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: reader) {
            collected.output = output.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global(qos: .utility).async(group: reader) {
            collected.errorOutput = errorOutput.fileHandleForReading.readDataToEndOfFile()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                finished.wait()
            }
            reader.wait()
            return .timedOut(seconds: Int(timeout.rounded(.up)))
        }
        reader.wait()

        return .exited(
            status: process.terminationStatus,
            output: String(decoding: collected.output, as: UTF8.self),
            errorOutput: String(decoding: collected.errorOutput, as: UTF8.self)
        )
    }
}

/// Each field is written by one reader and read only after both readers have
/// finished, which the dispatch group orders.
private final class CollectedOutput: @unchecked Sendable {
    var output = Data()
    var errorOutput = Data()
}
