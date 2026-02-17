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

}
