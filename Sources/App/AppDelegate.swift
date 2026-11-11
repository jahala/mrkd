import AppKit
import UniformTypeIdentifiers
import os
import os.signpost

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var pendingURLs: [URL] = []
    private var didFinishLaunching = false
    private var launchSignpostID: OSSignpostID?
    private var didCompleteFirstRender = false

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        FontRegistrar.registerBundledFonts()
        launchSignpostID = LaunchTimer.beginPhase("AppLaunch")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeFirstRender()

        checkQuickLookAtLaunch()

        // Build the main menu
        NSApp.mainMenu = MenuBuilder.buildMainMenu()

        // Bring app to the foreground (required for programmatic AppKit apps)
        NSApp.activate()

        didFinishLaunching = true

        if !pendingURLs.isEmpty {
            handleIncoming(pendingURLs)
            pendingURLs.removeAll()
        } else if !WindowManager.shared.restoreMostRecentDocument() {
            // `mrkd` with nothing to reopen — and a first launch — still has to
            // put something in front of the user.
            showOpenPanel()
        }
    }

    // MARK: - File Opening

    func application(_ application: NSApplication, open urls: [URL]) {
        // Accept any file when opened explicitly by user (via Open With, drag-and-drop)
        // Binary detection happens in FileReader
        if didFinishLaunching {
            handleIncoming(urls)
            NSApp.activate()
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    /// Everything that arrives as a URL — Finder, Open With, drag and drop, and
    /// the `mrkd` command. Markdown piped to the command arrives as a capsule
    /// in mrkd's own cache directory and is source, not a document on disk.
    private func handleIncoming(_ urls: [URL]) {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        for url in urls {
            if StdinCapsule.isCapsule(url, homeDirectory: home) {
                openStandardInputCapsule(url)
            } else {
                WindowManager.shared.openFile(url)
            }
        }
    }

    private func openStandardInputCapsule(_ url: URL) {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            try? FileManager.default.removeItem(at: url)
            WindowManager.shared.openStandardInput(source: source)
        } catch {
            // The capsule is left in place so the piped text is not lost.
            let alert = NSAlert()
            alert.messageText = "Couldn’t read the piped Markdown"
            alert.informativeText = "\(error.localizedDescription)\n\n\(url.path)"
            alert.runModal()
        }
    }

    /// `mrkd` with no arguments, or a click on the Dock icon, reopens the last
    /// document rather than leaving the user staring at an empty app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !WindowManager.shared.hasContentWindows else { return true }

        if !WindowManager.shared.restoreMostRecentDocument() {
            showOpenPanel()
        }
        return true
    }

    // MARK: - Window Lifecycle

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    // MARK: - Menu Actions

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
    }

    @objc func openDocument(_ sender: Any?) {
        showOpenPanel()
    }

    @objc func openFromClipboard(_ sender: Any?) {
        WindowManager.shared.openFromClipboard()
    }

    // MARK: - Open Panel

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            UTType(filenameExtension: "mdown") ?? .plainText,
            UTType(filenameExtension: "mkd") ?? .plainText,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose a Markdown file to view"

        let response = panel.runModal()
        if response == .OK {
            for url in panel.urls {
                WindowManager.shared.openFile(url)
            }
        } else {
            // User cancelled — no action needed, app stays open
        }
    }

    // MARK: - Launch Tracking

    private var firstRenderObserver: NSObjectProtocol?

    private func observeFirstRender() {
        firstRenderObserver = NotificationCenter.default.addObserver(
            forName: .markdownInitialRenderComplete,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notifyFirstRenderComplete()
        }
    }

    private func notifyFirstRenderComplete() {
        guard !didCompleteFirstRender, let signpostID = launchSignpostID else { return }
        didCompleteFirstRender = true
        LaunchTimer.endPhase("AppLaunch", id: signpostID)
    }

    // MARK: - Quick Look

    /// Registers this copy with Launch Services, refreshes the Quick Look
    /// extension after an update, and then, unless the user turned it off,
    /// checks that Quick Look will really show this copy's preview.
    ///
    /// Launch Services registration is what makes the extension discoverable
    /// when the app lives outside /Applications. The refresh after an update
    /// exists because Quick Look keeps the previous extension loaded; it runs
    /// before the check so the check sees the fresh registration.
    private func checkQuickLookAtLaunch() {
        let appURL = Bundle.main.bundleURL
        LSRegisterURL(appURL as CFURL, true)

        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let versionKey = "\(currentVersion)-\(buildNumber)"
        let versionChanged = UserDefaults.standard.string(forKey: "lastRegisteredVersion") != versionKey
        if versionChanged {
            UserDefaults.standard.set(versionKey, forKey: "lastRegisteredVersion")
        }

        // A build without the extension inside, such as `swift run`, has
        // nothing to refresh or check. Settings still says so when opened.
        let appex = QuickLookCheck.appexPath(appPath: appURL.path)
        guard FileManager.default.fileExists(atPath: appex) else { return }

        let checksAtLaunch = QuickLookCheckPreferences(defaults: .standard).checksAtLaunch
        guard versionChanged || checksAtLaunch else { return }

        Task.detached(priority: .utility) { [weak self] in
            var refreshFailure: String?
            if versionChanged {
                refreshFailure = QuickLookMaintenance.perform(QuickLookCheck.refreshSteps(appPath: appURL.path))
                if let refreshFailure {
                    Self.log.error("Quick Look refresh after update failed: \(refreshFailure, privacy: .public)")
                }
            }
            guard checksAtLaunch else { return }

            let report = QuickLookMaintenance.check(appURL: appURL)
            await self?.presentQuickLookProblem(report, refreshFailure: refreshFailure, appURL: appURL)
        }
    }

    private nonisolated static let log = Logger(subsystem: "com.mrkd.app", category: "QuickLook")

    /// One alert, only for a problem a button can fix, and not again for a
    /// problem the user already waved away.
    private func presentQuickLookProblem(_ report: QuickLookReport, refreshFailure: String?, appURL: URL) {
        let preferences = QuickLookCheckPreferences(defaults: .standard)
        let decision = QuickLookCheck.launchAlert(
            report: report,
            refreshFailure: refreshFailure,
            dismissed: preferences.dismissedProblem
        )
        preferences.dismissedProblem = decision.dismissed
        guard decision.show else { return }

        let home = URL(fileURLWithPath: NSHomeDirectory())
        var details = QuickLookCheck.statusText(report, homeDirectory: home)
        if let refreshFailure {
            details += "\n\nmrkd could not refresh Quick Look after the update: \(refreshFailure)."
        }

        let alert = NSAlert()
        alert.messageText = "Quick Look may not show mrkd’s preview"
        alert.informativeText = details
        alert.addButton(withTitle: QuickLookCheck.actionTitle(report.registration) ?? "Fix")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t check Quick Look when mrkd starts"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            preferences.checksAtLaunch = false
        }
        guard response == .alertFirstButtonReturn else {
            preferences.dismissedProblem = QuickLookCheck.problemKey(report)
            return
        }

        let steps = QuickLookCheck.repairSteps(for: report, appPath: appURL.path)
        Task.detached(priority: .userInitiated) {
            guard let failure = QuickLookMaintenance.perform(steps) else { return }
            await MainActor.run {
                let failed = NSAlert()
                failed.messageText = "Couldn’t fix Quick Look"
                failed.informativeText = failure + "."
                failed.runModal()
            }
        }
    }
}
