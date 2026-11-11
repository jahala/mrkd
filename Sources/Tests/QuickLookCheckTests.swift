import XCTest
@testable import mrkd

/// The Quick Look check reads `pluginkit` output. These tests feed it output
/// captured from real Macs, never the live system: the machine running the
/// tests has its own registrations, and they must not decide the result.
final class QuickLookCheckTests: XCTestCase {

    // MARK: - Captured output

    private static let installed = "/Applications/mrkd.app"
    private static let downloaded = "/Users/me/Downloads/mrkd.app"
    private static let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    private static func appex(_ app: String) -> String {
        app + "/Contents/PlugIns/QLPlugin.appex"
    }

    /// One entry as `pluginkit -m -A -D -vv` prints it.
    private static func entry(_ tag: String, version: String, app: String) -> String {
        """
        \(tag)    com.mrkd.app.QLPlugin(\(version))
        \t            Path = \(appex(app))
        \t            UUID = FD8B5A92-92CB-4E2A-8F91-6A7271D473F8
        \t       Timestamp = 2026-11-11 16:43:58 +0000
        \t             SDK = com.apple.quicklook.preview
        \t   Parent Bundle = \(app)
        \t    Display Name = mrkd Quick Look
        \t      Short Name = mrkd Quick Look
        \t     Parent Name = mrkd
        \t        Platform = macOS

        """
    }

    private static func listing(_ entries: [String]) -> String {
        let count = entries.count == 1 ? "(1 plug-in)" : "(\(entries.count) plug-ins)"
        return entries.joined() + " \(count)\n"
    }

    /// Captured on the Mac where the old copy won: 1.3.5 installed in
    /// /Applications, 1.4.0 run from Downloads, both registered and enabled.
    private static let twoCopies = listing([
        entry("+", version: "1.3.5", app: installed),
        entry("+", version: "1.4.0", app: downloaded),
    ])

    private static let noMatches = "  (no matches)\n"

    private func report(_ output: String, app: String = installed) -> QuickLookReport {
        QuickLookCheck.report(pluginkitOutput: output, appPath: app)
    }

    // MARK: - Registration status

    func testOneEnabledCopyThatIsThisOneIsHealthy() {
        let result = report(Self.listing([Self.entry("+", version: "1.4.0", app: Self.installed)]))
        XCTAssertEqual(result.registration, .healthy)
        XCTAssertFalse(result.outsideApplications)
    }

    func testTwoCopiesNameTheOtherOneFromEitherSide() {
        let fromDownloads = report(Self.twoCopies, app: Self.downloaded)
        XCTAssertEqual(fromDownloads.registration, .otherCopies([
            QuickLookRegistration(election: .use, version: "1.3.5", path: Self.appex(Self.installed)),
        ]))
        XCTAssertTrue(fromDownloads.outsideApplications)

        let fromApplications = report(Self.twoCopies, app: Self.installed)
        XCTAssertEqual(fromApplications.registration, .otherCopies([
            QuickLookRegistration(election: .use, version: "1.4.0", path: Self.appex(Self.downloaded)),
        ]))
        XCTAssertFalse(fromApplications.outsideApplications)
    }

    /// `-A` alone keeps one instance per version, which is why the check
    /// passes `-D`: two copies of the same release must both be seen.
    func testTwoCopiesOfTheSameVersionAreBothSeen() {
        let output = Self.listing([
            Self.entry("+", version: "1.4.0", app: Self.installed),
            Self.entry("+", version: "1.4.0", app: Self.downloaded),
        ])
        XCTAssertEqual(report(output).registration, .otherCopies([
            QuickLookRegistration(election: .use, version: "1.4.0", path: Self.appex(Self.downloaded)),
        ]))
        XCTAssertTrue(QuickLookCheck.listArguments.contains("-D"))
    }

    func testDisabledCopyIsDisabled() {
        let result = report(Self.listing([Self.entry("-", version: "1.4.0", app: Self.installed)]))
        XCTAssertEqual(result.registration, .disabled)
    }

    /// Only "use" and "use for debugging" put the preview in front of the
    /// user. Superseded or no election at all is not switched on.
    func testSupersededOrUnknownElectionIsNotSwitchedOn() {
        for tag in ["=", "?"] {
            let result = report(Self.listing([Self.entry(tag, version: "1.4.0", app: Self.installed)]))
            XCTAssertEqual(result.registration, .disabled, "tag \(tag)")
        }
        let debugging = report(Self.listing([Self.entry("!", version: "1.4.0", app: Self.installed)]))
        XCTAssertEqual(debugging.registration, .healthy)
    }

    func testNoMatchesIsNotRegistered() {
        XCTAssertEqual(report(Self.noMatches).registration, .notRegistered)
    }

    /// A different copy registered and this one missing still names the
    /// other copy: Use This Copy registers this one as well.
    func testOnlyAnotherCopyRegisteredNamesIt() {
        let output = Self.listing([Self.entry("+", version: "1.3.5", app: Self.installed)])
        XCTAssertEqual(report(output, app: Self.downloaded).registration, .otherCopies([
            QuickLookRegistration(election: .use, version: "1.3.5", path: Self.appex(Self.installed)),
        ]))
    }

    func testOtherCopyKeepsItsOwnElection() {
        let output = Self.listing([
            Self.entry("+", version: "1.4.0", app: Self.installed),
            Self.entry("-", version: "1.3.5", app: Self.downloaded),
        ])
        XCTAssertEqual(report(output).registration, .otherCopies([
            QuickLookRegistration(election: .ignore, version: "1.3.5", path: Self.appex(Self.downloaded)),
        ]))
    }

    func testPathsCompareAfterStandardising() {
        let output = Self.listing([Self.entry("+", version: "1.4.0", app: Self.installed)])
        XCTAssertEqual(report(output, app: "/Applications/./mrkd.app/").registration, .healthy)
    }

    func testEmptyOutputCannotBeChecked() {
        for output in ["", "   \n\n"] {
            guard case .couldNotCheck = report(output).registration else {
                return XCTFail("\(output.debugDescription) should not be read as a status")
            }
        }
    }

    func testGarbledOutputCannotBeChecked() {
        let garbled = [
            "pluginkit: connection to pkd interrupted\n",
            // An entry with no Path line.
            "+    com.mrkd.app.QLPlugin(1.4.0)\n (1 plug-in)\n",
            // Cut off before the summary line.
            String(Self.twoCopies.dropLast(" (2 plug-ins)\n".count)),
            // The summary disagrees with what was listed.
            Self.entry("+", version: "1.4.0", app: Self.installed) + " (2 plug-ins)\n",
            // A line in a shape pluginkit does not print.
            Self.entry("+", version: "1.4.0", app: Self.installed) + "something else\n (1 plug-in)\n",
        ]
        for output in garbled {
            guard case .couldNotCheck = report(output).registration else {
                return XCTFail("\(output.debugDescription) should not be read as a status")
            }
        }
    }

    /// Captured from `pluginkit -m -A -D -vv` on macOS 27. Pins the parser to
    /// the real spacing rather than to the helper above.
    func testRealCapturedOutputParses() {
        let captured = "+    com.mrkd.app.QLPlugin(1.3.5)\n"
            + "\t            Path = /Applications/mrkd.app/Contents/PlugIns/QLPlugin.appex\n"
            + "\t            UUID = FD8B5A92-92CB-4E2A-8F91-6A7271D473F8\n"
            + "\t       Timestamp = 2026-11-11 16:43:58 +0000\n"
            + "\t             SDK = com.apple.quicklook.preview\n"
            + "\t   Parent Bundle = /Applications/mrkd.app\n"
            + "\t    Display Name = mrkd Quick Look\n"
            + "\t      Short Name = mrkd Quick Look\n"
            + "\t     Parent Name = mrkd\n"
            + "\t        Platform = macOS\n"
            + "\n"
            + "+    com.mrkd.app.QLPlugin(1.4.0)\n"
            + "\t            Path = /Users/me/Downloads/mrkd.app/Contents/PlugIns/QLPlugin.appex\n"
            + "\t            UUID = 8D9C6A9F-6DE7-4952-B6B5-F26CE72648AD\n"
            + "\t       Timestamp = 2026-11-11 16:50:56 +0000\n"
            + "\t             SDK = com.apple.quicklook.preview\n"
            + "\t   Parent Bundle = /Users/me/Downloads/mrkd.app\n"
            + "\t    Display Name = mrkd Quick Look\n"
            + "\t      Short Name = mrkd Quick Look\n"
            + "\t     Parent Name = mrkd\n"
            + "\t        Platform = macOS\n"
            + "\n"
            + " (2 plug-ins)\n"
        XCTAssertEqual(QuickLookCheck.registrations(in: captured), [
            QuickLookRegistration(election: .use, version: "1.3.5", path: Self.appex(Self.installed)),
            QuickLookRegistration(election: .use, version: "1.4.0", path: Self.appex(Self.downloaded)),
        ])
        XCTAssertEqual(QuickLookCheck.registrations(in: Self.noMatches), [])
        XCTAssertNil(QuickLookCheck.registrations(in: ""))
    }

    // MARK: - Location

    func testOnlyAppsInApplicationsReachTheirFonts() {
        XCTAssertFalse(QuickLookCheck.isOutsideApplications(appPath: "/Applications/mrkd.app"))
        XCTAssertFalse(QuickLookCheck.isOutsideApplications(appPath: "/Applications/Tools/mrkd.app"))
        XCTAssertTrue(QuickLookCheck.isOutsideApplications(appPath: "/Users/me/Applications/mrkd.app"))
        XCTAssertTrue(QuickLookCheck.isOutsideApplications(appPath: "/Users/me/Downloads/mrkd.app"))
        XCTAssertTrue(QuickLookCheck.isOutsideApplications(appPath: "/ApplicationsOld/mrkd.app"))
    }

    // MARK: - Words and actions

    func testStatusTextNamesEachOtherCopyAndWarnsTheyCanComeBack() {
        let text = QuickLookCheck.statusText(report(Self.twoCopies, app: Self.downloaded), homeDirectory: Self.home)
        XCTAssertTrue(text.contains("1.3.5"), text)
        XCTAssertTrue(text.contains("/Applications/mrkd.app"), text)
        XCTAssertFalse(text.contains("QLPlugin.appex"), "show the app, not its insides: \(text)")
        XCTAssertTrue(text.contains("register it again"), text)
        XCTAssertTrue(text.contains("system font"), "running from Downloads: \(text)")

        let other = QuickLookCheck.statusText(report(Self.twoCopies, app: Self.installed), homeDirectory: Self.home)
        XCTAssertTrue(other.contains("~/Downloads/mrkd.app"), other)
        XCTAssertFalse(other.contains("system font"), "running from /Applications: \(other)")
    }

    /// A pluginkit that fails or stalls must never read as "not registered":
    /// that would offer a Fix for a problem nobody has seen.
    func testAFailedListingIsReportedNotRead() {
        let failed = QuickLookCheck.report(
            listOutcome: .exited(status: 1, output: Self.noMatches, errorOutput: "pkd is not running\n"),
            appPath: Self.installed
        )
        XCTAssertEqual(failed.registration, .couldNotCheck(
            "/usr/bin/pluginkit -m -A -D -vv -i com.mrkd.app.QLPlugin stopped with status 1: pkd is not running."
        ))

        let stalled = QuickLookCheck.report(listOutcome: .timedOut(seconds: 20), appPath: Self.downloaded)
        guard case .couldNotCheck(let reason) = stalled.registration else { return XCTFail("\(stalled)") }
        XCTAssertTrue(reason.contains("did not finish within 20 seconds"), reason)
        XCTAssertTrue(stalled.outsideApplications)

        let fine = QuickLookCheck.report(
            listOutcome: .exited(status: 0, output: Self.noMatches, errorOutput: ""),
            appPath: Self.installed
        )
        XCTAssertEqual(fine.registration, .notRegistered)
    }

    func testCouldNotCheckSaysWhy() {
        let result = QuickLookReport(registration: .couldNotCheck("pluginkit exited with status 1."), outsideApplications: false)
        XCTAssertTrue(QuickLookCheck.statusText(result, homeDirectory: Self.home).contains("pluginkit exited with status 1."))
    }

    /// Settings shows a word or two and a button. The full explanation is
    /// for the tooltip and the launch alert, never the panel itself.
    func testSettingsShowsAShortStatus() {
        let other = QuickLookRegistration(election: .use, version: "1.3.5", path: Self.appex(Self.installed))
        func label(_ status: QuickLookRegistrationStatus, outside: Bool = false) -> QuickLookCheck.SettingsLabel {
            QuickLookCheck.settingsLabel(QuickLookReport(registration: status, outsideApplications: outside))
        }
        XCTAssertEqual(label(.healthy), .init(status: "Working", note: nil))
        XCTAssertEqual(label(.notRegistered), .init(status: "Not set up", note: nil))
        XCTAssertEqual(label(.disabled), .init(status: "Turned off", note: nil))
        XCTAssertEqual(label(.otherCopies([other])), .init(status: "Another copy of mrkd may be used", note: nil))
        XCTAssertEqual(label(.couldNotCheck("pkd is not running.")), .init(status: "Couldn’t check", note: nil))
        XCTAssertEqual(
            label(.healthy, outside: true),
            .init(status: "Working", note: "Previews use the system font until mrkd is in Applications.")
        )
    }

    func testEachStatusHasItsOwnAction() {
        let other = QuickLookRegistration(election: .use, version: "1.3.5", path: Self.appex(Self.installed))
        XCTAssertNil(QuickLookCheck.actionTitle(.healthy))
        XCTAssertNil(QuickLookCheck.actionTitle(.couldNotCheck("x")))
        XCTAssertEqual(QuickLookCheck.actionTitle(.notRegistered), "Fix")
        XCTAssertEqual(QuickLookCheck.actionTitle(.disabled), "Fix")
        XCTAssertEqual(QuickLookCheck.actionTitle(.otherCopies([other])), "Use This Copy")
    }

    // MARK: - Commands

    func testUseThisCopyRemovesTheOthersBeforeRegisteringThisOne() {
        let steps = QuickLookCheck.repairSteps(for: report(Self.twoCopies, app: Self.downloaded), appPath: Self.downloaded)
        XCTAssertEqual(steps.map(\.commandLine), [
            "/usr/bin/pluginkit -r \(Self.appex(Self.installed))",
            "/usr/bin/pluginkit -a \(Self.appex(Self.downloaded))",
            "/usr/bin/pluginkit -e use -i com.mrkd.app.QLPlugin",
            "/usr/bin/killall QLPlugin",
            "/usr/bin/qlmanage -r",
            "/usr/bin/qlmanage -r cache",
            "/usr/bin/killall QuickLookUIService",
        ])
    }

    func testFixRegistersAndSwitchesOnThisCopyOnly() {
        let steps = QuickLookCheck.repairSteps(for: report(Self.noMatches), appPath: Self.installed)
        XCTAssertFalse(steps.contains { $0.commandLine.hasPrefix("/usr/bin/pluginkit -r") })
        XCTAssertEqual(steps.first?.commandLine, "/usr/bin/pluginkit -a \(Self.appex(Self.installed))")
        XCTAssertTrue(steps.contains { $0.commandLine == "/usr/bin/pluginkit -e use -i com.mrkd.app.QLPlugin" })
    }

    /// An update refreshes the registration but leaves the user's own
    /// on/off choice alone: switching on is only for an explicit Fix.
    func testUpdateRefreshDoesNotOverrideTheUsersChoice() {
        let steps = QuickLookCheck.refreshSteps(appPath: Self.installed)
        XCTAssertEqual(steps.first?.commandLine, "/usr/bin/pluginkit -a \(Self.appex(Self.installed))")
        XCTAssertFalse(steps.contains { $0.commandLine.hasPrefix("/usr/bin/pluginkit -e") || $0.commandLine.hasPrefix("/usr/bin/pluginkit -r") })
        XCTAssertTrue(steps.contains { $0.commandLine == "/usr/bin/qlmanage -r cache" })
    }

    func testFailuresAreReportedAndKillallWithNothingToStopIsNot() {
        let pluginkit = QuickLookStep(executable: "/usr/bin/pluginkit", arguments: ["-a", "/x.appex"])
        let killall = QuickLookStep.killall("QLPlugin")

        XCTAssertNil(QuickLookCheck.failure(of: pluginkit, .exited(status: 0, output: "", errorOutput: "")))
        XCTAssertNil(QuickLookCheck.failure(of: killall, .exited(status: 1, output: "", errorOutput: "No matching processes belonging to you were found\n")))

        let failed = QuickLookCheck.failure(of: pluginkit, .exited(status: 2, output: "", errorOutput: "pkd refused\n"))
        XCTAssertEqual(failed, "/usr/bin/pluginkit -a /x.appex stopped with status 2: pkd refused")

        XCTAssertNotNil(QuickLookCheck.failure(of: killall, .exited(status: 2, output: "", errorOutput: "")))
        XCTAssertEqual(
            QuickLookCheck.failure(of: pluginkit, .couldNotStart("no such file")),
            "/usr/bin/pluginkit -a /x.appex could not start: no such file"
        )
        XCTAssertEqual(
            QuickLookCheck.failure(of: pluginkit, .timedOut(seconds: 20)),
            "/usr/bin/pluginkit -a /x.appex did not finish within 20 seconds"
        )
    }

    // MARK: - Remembering a dismissed problem

    func testADismissedProblemStaysQuietUntilItChanges() {
        let notRegistered = report(Self.noMatches)
        let twoCopies = report(Self.twoCopies)
        let healthy = report(Self.listing([Self.entry("+", version: "1.4.0", app: Self.installed)]))

        // First launch with a problem: ask.
        var dismissed: String? = nil
        var decision = QuickLookCheck.launchAlert(report: notRegistered, refreshFailure: nil, dismissed: dismissed)
        XCTAssertTrue(decision.show)
        // The user says Not now.
        dismissed = QuickLookCheck.problemKey(notRegistered)
        XCTAssertNotNil(dismissed)

        // Same problem next launch: quiet.
        decision = QuickLookCheck.launchAlert(report: notRegistered, refreshFailure: nil, dismissed: dismissed)
        XCTAssertFalse(decision.show)
        dismissed = decision.dismissed

        // A different problem: ask again.
        decision = QuickLookCheck.launchAlert(report: twoCopies, refreshFailure: nil, dismissed: dismissed)
        XCTAssertTrue(decision.show)

        // A clean check forgets the dismissal, so the old problem coming
        // back later is news again.
        decision = QuickLookCheck.launchAlert(report: healthy, refreshFailure: nil, dismissed: dismissed)
        XCTAssertFalse(decision.show)
        XCTAssertNil(decision.dismissed)
        decision = QuickLookCheck.launchAlert(report: notRegistered, refreshFailure: nil, dismissed: decision.dismissed)
        XCTAssertTrue(decision.show)
    }

    func testANewOtherCopyIsADifferentProblem() {
        let one = report(Self.twoCopies)
        let two = report(Self.listing([
            Self.entry("+", version: "1.4.0", app: Self.installed),
            Self.entry("+", version: "1.3.5", app: Self.downloaded),
            Self.entry("+", version: "1.5.0", app: "/Users/me/Desktop/mrkd.app"),
        ]))
        XCTAssertNotEqual(QuickLookCheck.problemKey(one), QuickLookCheck.problemKey(two))
    }

    func testOnlyFixableProblemsAsk() {
        let outside = report(Self.listing([Self.entry("+", version: "1.4.0", app: Self.downloaded)]), app: Self.downloaded)
        XCTAssertEqual(outside.registration, .healthy)
        XCTAssertTrue(outside.outsideApplications)
        XCTAssertNil(QuickLookCheck.problemKey(outside))
        XCTAssertFalse(QuickLookCheck.launchAlert(report: outside, refreshFailure: nil, dismissed: nil).show)

        let unknown = report("")
        XCTAssertNil(QuickLookCheck.problemKey(unknown))
        XCTAssertFalse(QuickLookCheck.launchAlert(report: unknown, refreshFailure: nil, dismissed: nil).show)
    }

    /// The refresh after an update runs once per version, so its failure is
    /// shown even when the registration looks fine afterwards.
    func testAFailedUpdateRefreshAsks() {
        let healthy = report(Self.listing([Self.entry("+", version: "1.4.0", app: Self.installed)]))
        let decision = QuickLookCheck.launchAlert(report: healthy, refreshFailure: "qlmanage -r stopped with status 1", dismissed: nil)
        XCTAssertTrue(decision.show)
    }
}

/// The two settings the launch check keeps, stored in the app's defaults.
final class QuickLookCheckPreferencesTests: XCTestCase {

    private var saved: [String: Any] = [:]
    private let keys = [QuickLookCheckPreferences.checkAtLaunchKey, QuickLookCheckPreferences.dismissedProblemKey]

    override func setUp() {
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            UserDefaults.standard.set(saved[key], forKey: key)
        }
    }

    func testTheCheckIsOnByDefault() {
        XCTAssertTrue(QuickLookCheckPreferences(defaults: .standard).checksAtLaunch)
    }

    func testSettingsSurviveANewReader() {
        let preferences = QuickLookCheckPreferences(defaults: .standard)
        preferences.checksAtLaunch = false
        preferences.dismissedProblem = "disabled|/Applications/mrkd.app/Contents/PlugIns/QLPlugin.appex"

        let reread = QuickLookCheckPreferences(defaults: .standard)
        XCTAssertFalse(reread.checksAtLaunch)
        XCTAssertEqual(reread.dismissedProblem, "disabled|/Applications/mrkd.app/Contents/PlugIns/QLPlugin.appex")

        preferences.dismissedProblem = nil
        XCTAssertNil(QuickLookCheckPreferences(defaults: .standard).dismissedProblem)
    }
}

/// The command runner, exercised on throwaway shell commands. It never runs
/// pluginkit or qlmanage here: those would change this Mac's registrations.
final class QuickLookMaintenanceTests: XCTestCase {

    private func shell(_ script: String) -> QuickLookStep {
        QuickLookStep(executable: "/bin/sh", arguments: ["-c", script])
    }

    func testCollectsOutputErrorOutputAndStatus() {
        let outcome = QuickLookMaintenance.run(shell("echo listed; echo complained >&2; exit 3"))
        XCTAssertEqual(outcome, .exited(status: 3, output: "listed\n", errorOutput: "complained\n"))
    }

    /// More than a pipe buffer on each stream: a runner that drains only
    /// one stream, or drains them only after the exit, would hang here.
    func testLargeOutputOnBothStreamsDoesNotStall() {
        let outcome = QuickLookMaintenance.run(
            shell("head -c 200000 /dev/zero | tr '\\0' a; head -c 200000 /dev/zero | tr '\\0' b >&2"),
            timeout: 30
        )
        guard case .exited(0, let output, let errorOutput) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(output.count, 200000)
        XCTAssertEqual(errorOutput.count, 200000)
    }

    func testAStalledCommandIsStoppedAndReported() {
        let outcome = QuickLookMaintenance.run(shell("exec sleep 30"), timeout: 0.3)
        XCTAssertEqual(outcome, .timedOut(seconds: 1))
    }

    func testAMissingExecutableIsReported() {
        let step = QuickLookStep(executable: "/nonexistent/mrkd-test-tool", arguments: [])
        guard case .couldNotStart = QuickLookMaintenance.run(step) else { return XCTFail() }
    }

    func testPerformStopsAtTheFirstFailure() throws {
        let marker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-ql-perform-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }

        let failure = QuickLookMaintenance.perform([
            shell("exit 0"),
            shell("echo refused >&2; exit 4"),
            shell("touch '\(marker.path)'"),
        ])
        XCTAssertEqual(failure, "/bin/sh -c echo refused >&2; exit 4 stopped with status 4: refused")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "a step after the failure ran")
        XCTAssertNil(QuickLookMaintenance.perform([shell("exit 0"), shell("exit 0")]))
    }
}
