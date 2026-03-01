import AppKit
import UniformTypeIdentifiers
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
        // Register with Launch Services so the bundled Quick Look extension
        // is discoverable even when the app lives outside /Applications.
        registerWithLaunchServices()

        // Build the main menu
        NSApp.mainMenu = MenuBuilder.buildMainMenu()

        // Bring app to the foreground (required for programmatic AppKit apps)
        NSApp.activate()

        didFinishLaunching = true

        if pendingURLs.isEmpty {
            // Launched without a file — show Open dialog
            showOpenPanel()
        } else {
            for url in pendingURLs {
                WindowManager.shared.openFile(url)
            }
            pendingURLs.removeAll()
        }
    }

    // MARK: - File Opening

    func application(_ application: NSApplication, open urls: [URL]) {
        // Accept any file when opened explicitly by user (via Open With, drag-and-drop)
        // Binary detection happens in FileReader
        if didFinishLaunching {
            for url in urls {
                WindowManager.shared.openFile(url)
            }
            NSApp.activate()
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    // MARK: - Window Lifecycle

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return true
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
            // User cancelled — quit since there are no windows
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Launch Tracking

    func notifyFirstRenderComplete() {
        guard !didCompleteFirstRender, let signpostID = launchSignpostID else { return }
        didCompleteFirstRender = true
        LaunchTimer.endPhase("AppLaunch", id: signpostID)
    }

    // MARK: - Quick Look Registration

    private func registerWithLaunchServices() {
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else { return }
        LSRegisterURL(bundleURL, true)

        // When the app version changes, reset the Quick Look cache so macOS
        // picks up the updated QL extension binary instead of the cached one.
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let versionKey = "\(currentVersion)-\(buildNumber)"
        let lastVersion = UserDefaults.standard.string(forKey: "lastRegisteredVersion")

        if lastVersion != versionKey {
            UserDefaults.standard.set(versionKey, forKey: "lastRegisteredVersion")
            refreshQuickLookExtension()
        }
    }

    /// Force macOS to pick up the updated Quick Look extension after an app update.
    /// The QL extension runs as a separate long-lived process; simply replacing the
    /// .app bundle doesn't cause it to reload. We need to:
    /// 1. Re-register the appex with pluginkit
    /// 2. Reset the Quick Look server and preview cache
    /// 3. Kill QuickLookUIService which caches the loaded extension
    private func refreshQuickLookExtension() {
        Task.detached(priority: .utility) {
            let appexPath = Bundle.main.builtInPlugInsURL?
                .appendingPathComponent("QLPlugin.appex").path ?? ""

            // Kill the running QL extension process so macOS loads the new binary.
            Self.runProcess("/usr/bin/killall", arguments: ["QLPlugin"])

            // Re-register the extension with the plugin system.
            if !appexPath.isEmpty {
                Self.runProcess("/usr/bin/pluginkit", arguments: ["-a", appexPath])
            }

            // Reset the Quick Look server and preview cache.
            Self.runProcess("/usr/bin/qlmanage", arguments: ["-r"])
            Self.runProcess("/usr/bin/qlmanage", arguments: ["-r", "cache"])

            // Kill the QuickLookUIService that caches loaded extensions.
            Self.runProcess("/usr/bin/killall", arguments: ["QuickLookUIService"])
        }
    }

    private nonisolated static func runProcess(_ path: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = nil
        process.standardError = nil
        try? process.run()
        process.waitUntilExit()
    }

}
