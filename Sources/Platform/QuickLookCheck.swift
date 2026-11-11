import Foundation

/// One registered copy of mrkd's Quick Look extension, as `pluginkit` lists it.
struct QuickLookRegistration: Equatable, Sendable {

    /// The tag `pluginkit -m` prints at the start of each entry.
    enum Election: Equatable, Sendable {
        case use          // +
        case ignore       // -
        case debug        // !  use, for debugger runs
        case superseded   // =  another plug-in won
        case unknown      // ?  or no tag at all
    }

    let election: Election
    let version: String
    /// The extension's own path, `…/mrkd.app/Contents/PlugIns/QLPlugin.appex`.
    let path: String

    var isSwitchedOn: Bool { election == .use || election == .debug }
}

enum QuickLookRegistrationStatus: Equatable, Sendable {
    /// This copy is registered and switched on, and no other copy is.
    case healthy
    /// macOS does not know about this copy's extension.
    case notRegistered
    /// This copy is registered but not switched on.
    case disabled
    /// Other copies of mrkd are registered too, and Quick Look may pick one
    /// of them. Takes priority over this copy's own state, because Use This
    /// Copy re-registers and switches on this copy as well.
    case otherCopies([QuickLookRegistration])
    /// The check itself failed. Carries the reason, in words.
    case couldNotCheck(String)
}

struct QuickLookReport: Equatable, Sendable {
    let registration: QuickLookRegistrationStatus
    /// The sandboxed preview can only read mrkd's bundled fonts when the app
    /// is in /Applications (see `BundledFonts`). Anywhere else the preview
    /// is set in the system font. No button fixes this; moving the app does.
    let outsideApplications: Bool
}

/// One command the check or a repair runs.
struct QuickLookStep: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    /// `killall` exits 1 when nothing was running. For a repair that is
    /// the same as success: there was no stale process to stop.
    var nothingToStopIsFine = false

    static func killall(_ name: String) -> QuickLookStep {
        QuickLookStep(executable: "/usr/bin/killall", arguments: [name], nothingToStopIsFine: true)
    }

    var commandLine: String { ([executable] + arguments).joined(separator: " ") }
}

/// How a command ended.
enum QuickLookCommandOutcome: Equatable, Sendable {
    case exited(status: Int32, output: String, errorOutput: String)
    case couldNotStart(String)
    case timedOut(seconds: Int)
}

/// Whether Quick Look will show mrkd's preview, decided from `pluginkit`'s
/// answer. Everything here is a function of its inputs; the commands are run
/// by `QuickLookMaintenance`.
enum QuickLookCheck {

    static let extensionIdentifier = "com.mrkd.app.QLPlugin"

    /// `-A` lists every version and `-D` every copy of each version: with
    /// `-A` alone, two copies of the same release show up as one. `-vv`
    /// prints each entry with labelled lines (`Path = …`); a single `-v`
    /// prints unlabelled tab-separated columns instead.
    static let listArguments = ["-m", "-A", "-D", "-vv", "-i", extensionIdentifier]

    static var listStep: QuickLookStep {
        QuickLookStep(executable: "/usr/bin/pluginkit", arguments: listArguments)
    }

    static func appexPath(appPath: String) -> String {
        (appPath as NSString).appendingPathComponent("Contents/PlugIns/QLPlugin.appex")
    }

    // MARK: - Reading pluginkit

    /// The registrations in `pluginkit -m -vv` output, or nil when the output
    /// is not in the shape pluginkit prints. Nil rather than a guess: a
    /// misread listing would offer to remove registrations that are fine.
    static func registrations(in output: String) -> [QuickLookRegistration]? {
        var found: [QuickLookRegistration] = []
        var pending: (election: QuickLookRegistration.Election, version: String)?
        var summaryCount: Int?

        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard summaryCount == nil else { return nil }   // nothing follows the summary

            if rawLine.hasPrefix("\t") {
                guard let separator = line.range(of: " = ") else { return nil }
                if line[..<separator.lowerBound] == "Path" {
                    guard let entry = pending else { return nil }
                    found.append(QuickLookRegistration(
                        election: entry.election,
                        version: entry.version,
                        path: String(line[separator.upperBound...])
                    ))
                    pending = nil
                }
            } else if let header = entryHeader(rawLine) {
                // An entry without a Path line cannot be compared or removed.
                guard pending == nil else { return nil }
                pending = header
            } else if let count = summary(line) {
                guard pending == nil else { return nil }
                summaryCount = count
            } else {
                return nil
            }
        }

        guard let summaryCount, summaryCount == found.count else { return nil }
        return found
    }

    /// `+    com.mrkd.app.QLPlugin(1.4.0)`: a one-character election tag
    /// (a space when there is none), padding, then identifier(version).
    private static func entryHeader(_ line: String) -> (election: QuickLookRegistration.Election, version: String)? {
        guard let tag = line.first else { return nil }
        let election: QuickLookRegistration.Election
        switch tag {
        case "+": election = .use
        case "-": election = .ignore
        case "!": election = .debug
        case "=": election = .superseded
        case "?", " ": election = .unknown
        default: return nil
        }
        let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
        let prefix = extensionIdentifier + "("
        guard rest.hasPrefix(prefix), rest.hasSuffix(")") else { return nil }
        let version = rest.dropFirst(prefix.count).dropLast()
        guard !version.isEmpty, !version.contains("("), !version.contains(")") else { return nil }
        return (election, String(version))
    }

    /// ` (2 plug-ins)`, ` (1 plug-in)` or `  (no matches)`.
    private static func summary(_ line: String) -> Int? {
        if line == "(no matches)" { return 0 }
        guard line.hasPrefix("("), line.hasSuffix(")") else { return nil }
        let words = line.dropFirst().dropLast().split(separator: " ")
        guard words.count == 2, words[1] == "plug-in" || words[1] == "plug-ins",
              let count = Int(words[0]) else { return nil }
        return count
    }

    // MARK: - The check

    /// The report for however `listStep` ended. A failed or stalled pluginkit
    /// is reported as such, never read as "not registered".
    static func report(listOutcome: QuickLookCommandOutcome, appPath: String) -> QuickLookReport {
        if case .exited(0, let output, _) = listOutcome {
            return report(pluginkitOutput: output, appPath: appPath)
        }
        let reason = failure(of: listStep, listOutcome) ?? "\(listStep.commandLine) failed"
        return QuickLookReport(
            registration: .couldNotCheck(reason + "."),
            outsideApplications: isOutsideApplications(appPath: appPath)
        )
    }

    static func report(pluginkitOutput: String, appPath: String) -> QuickLookReport {
        QuickLookReport(
            registration: registrationStatus(pluginkitOutput: pluginkitOutput, appPath: appPath),
            outsideApplications: isOutsideApplications(appPath: appPath)
        )
    }

    private static func registrationStatus(pluginkitOutput: String, appPath: String) -> QuickLookRegistrationStatus {
        guard let registrations = registrations(in: pluginkitOutput) else {
            let trimmed = pluginkitOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return .couldNotCheck(trimmed.isEmpty
                ? "pluginkit printed nothing."
                : "pluginkit printed something mrkd does not recognise:\n\(trimmed.prefix(300))")
        }

        let ownPath = standardized(appexPath(appPath: appPath))
        let own = registrations.filter { standardized($0.path) == ownPath }

        var seen = Set<String>()
        let others = registrations.filter {
            let path = standardized($0.path)
            return path != ownPath && seen.insert(path).inserted
        }

        if !others.isEmpty { return .otherCopies(others) }
        if own.isEmpty { return .notRegistered }
        return own.contains(where: \.isSwitchedOn) ? .healthy : .disabled
    }

    static func isOutsideApplications(appPath: String) -> Bool {
        !standardized(appPath).hasPrefix("/Applications/")
    }

    /// Removes `.`, `..` and trailing slashes without touching the disk.
    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardized.path
    }

    // MARK: - Words

    /// The status in plain words, one paragraph per fact.
    static func statusText(_ report: QuickLookReport, homeDirectory: URL) -> String {
        var paragraphs: [String]
        switch report.registration {
        case .healthy:
            paragraphs = ["Quick Look shows mrkd’s preview, from this copy of mrkd."]
        case .notRegistered:
            paragraphs = ["macOS has no record of this copy’s Quick Look preview, so Finder will not show it. "
                + "Fix registers it again."]
        case .disabled:
            paragraphs = ["mrkd’s Quick Look preview is switched off. Fix switches it on."]
        case .otherCopies(let others):
            let list = others.map { other in
                let state = other.isSwitchedOn ? "" : " (switched off)"
                return "    \(other.version) at \(displayAppPath(other.path, homeDirectory: homeDirectory))\(state)"
            }
            paragraphs = [
                (["Other copies of mrkd also offer a Quick Look preview, and Finder may use one of them instead:"]
                    + list).joined(separator: "\n"),
                "Use This Copy removes their Quick Look registrations. It does not delete or move them, "
                    + "and opening another copy can register it again.",
            ]
        case .couldNotCheck(let reason):
            paragraphs = ["mrkd could not check Quick Look. \(reason)"]
        }
        if report.outsideApplications {
            paragraphs.append("mrkd is not in your Applications folder, so Quick Look previews use the system font. "
                + "Move mrkd to Applications to preview in its own fonts.")
        }
        return paragraphs.joined(separator: "\n\n")
    }

    /// The app a registration belongs to, written the way Finder users know it.
    private static func displayAppPath(_ appexPath: String, homeDirectory: URL) -> String {
        let suffix = "/Contents/PlugIns/QLPlugin.appex"
        let app = appexPath.hasSuffix(suffix) ? String(appexPath.dropLast(suffix.count)) : appexPath
        return CommandLineLauncher.displayPath(URL(fileURLWithPath: app, isDirectory: true), homeDirectory: homeDirectory)
    }

    /// What the Settings row shows: a status of a word or two, and a short
    /// note when previews can't use mrkd's fonts. The full `statusText` goes
    /// in the row's tooltip and in the launch alert.
    struct SettingsLabel: Equatable {
        let status: String
        let note: String?
    }

    static func settingsLabel(_ report: QuickLookReport) -> SettingsLabel {
        let status: String
        switch report.registration {
        case .healthy: status = "Working"
        case .notRegistered: status = "Not set up"
        case .disabled: status = "Turned off"
        case .otherCopies: status = "Another copy of mrkd may be used"
        case .couldNotCheck: status = "Couldn’t check"
        }
        let note = report.outsideApplications
            ? "Previews use the system font until mrkd is in Applications."
            : nil
        return SettingsLabel(status: status, note: note)
    }

    /// The button for a status, or nil when there is nothing a button can do.
    static func actionTitle(_ status: QuickLookRegistrationStatus) -> String? {
        switch status {
        case .healthy, .couldNotCheck: return nil
        case .notRegistered, .disabled: return "Fix"
        case .otherCopies: return "Use This Copy"
        }
    }

    // MARK: - Commands

    /// Fix and Use This Copy. Other copies are removed first, so if one of
    /// them turns out to be this copy under another spelling, the add that
    /// follows puts it straight back.
    static func repairSteps(for report: QuickLookReport, appPath: String) -> [QuickLookStep] {
        var removals: [String] = []
        if case .otherCopies(let others) = report.registration {
            removals = others.map(\.path)
        }
        return steps(appPath: appPath, removing: removals, switchOn: true)
    }

    /// After mrkd is updated, Quick Look keeps the old extension loaded until
    /// it is registered again and the Quick Look processes restart. This does
    /// that, and leaves the user's own on/off choice for the preview alone.
    static func refreshSteps(appPath: String) -> [QuickLookStep] {
        steps(appPath: appPath, removing: [], switchOn: false)
    }

    private static func steps(appPath: String, removing: [String], switchOn: Bool) -> [QuickLookStep] {
        let pluginkit = "/usr/bin/pluginkit"
        var steps = removing.map { QuickLookStep(executable: pluginkit, arguments: ["-r", $0]) }
        steps.append(QuickLookStep(executable: pluginkit, arguments: ["-a", appexPath(appPath: appPath)]))
        if switchOn {
            steps.append(QuickLookStep(executable: pluginkit, arguments: ["-e", "use", "-i", extensionIdentifier]))
        }
        steps += [
            // The extension runs as a long-lived process that keeps the old
            // binary loaded, and Quick Look caches both it and its previews.
            .killall("QLPlugin"),
            QuickLookStep(executable: "/usr/bin/qlmanage", arguments: ["-r"]),
            QuickLookStep(executable: "/usr/bin/qlmanage", arguments: ["-r", "cache"]),
            .killall("QuickLookUIService"),
        ]
        return steps
    }

    /// What went wrong with a command, in words, or nil when it succeeded.
    static func failure(of step: QuickLookStep, _ outcome: QuickLookCommandOutcome) -> String? {
        switch outcome {
        case .exited(let status, _, let errorOutput):
            if status == 0 || (status == 1 && step.nothingToStopIsFine) { return nil }
            let detail = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(step.commandLine) stopped with status \(status)" + (detail.isEmpty ? "" : ": \(detail)")
        case .couldNotStart(let reason):
            return "\(step.commandLine) could not start: \(reason)"
        case .timedOut(let seconds):
            return "\(step.commandLine) did not finish within \(seconds) seconds"
        }
    }

    // MARK: - The launch check

    /// A stable name for a problem a button can fix, or nil when there is
    /// none. Remembered when the user says Not now, so the same unchanged
    /// problem does not ask again on every launch.
    static func problemKey(_ report: QuickLookReport) -> String? {
        switch report.registration {
        case .healthy, .couldNotCheck:
            return nil
        case .notRegistered:
            return "notRegistered"
        case .disabled:
            return "disabled"
        case .otherCopies(let others):
            let copies = others.map { "\($0.version)@\(standardized($0.path))" }.sorted()
            return "otherCopies|" + copies.joined(separator: "|")
        }
    }

    /// Whether launch should ask, and what to remember afterwards. A clean
    /// check forgets the dismissed problem, so it is news if it comes back.
    /// A failed update refresh always asks: it runs once per version, so it
    /// cannot repeat on every launch.
    static func launchAlert(
        report: QuickLookReport,
        refreshFailure: String?,
        dismissed: String?
    ) -> (show: Bool, dismissed: String?) {
        guard let key = problemKey(report) else {
            return (refreshFailure != nil, nil)
        }
        return (refreshFailure != nil || key != dismissed, dismissed)
    }
}

/// The launch check's two settings, kept in the app's own defaults. The Quick
/// Look extension never reads them.
struct QuickLookCheckPreferences {

    static let checkAtLaunchKey = "checkQuickLookAtLaunch"
    static let dismissedProblemKey = "dismissedQuickLookProblem"

    let defaults: UserDefaults

    /// On unless the user turned it off.
    var checksAtLaunch: Bool {
        get { defaults.object(forKey: Self.checkAtLaunchKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.checkAtLaunchKey) }
    }

    var dismissedProblem: String? {
        get { defaults.string(forKey: Self.dismissedProblemKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.dismissedProblemKey) }
    }
}
