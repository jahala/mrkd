import AppKit

@MainActor
final class WindowManager: NSObject {

    static let shared = WindowManager()

    private var windows: [NSWindow] = []
    private var themeObserver: NSObjectProtocol?

    private override init() {
        super.init()
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.themeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowMinSizes()
            }
        }
    }

    /// Any mrkd content window — documents and source windows, not Settings.
    var hasContentWindows: Bool {
        !windows.isEmpty
    }

    func openFile(_ url: URL) {
        // Record this file for Open Recent menu
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        // A second `mrkd plan.md` focuses the window already showing that file
        // rather than stacking a duplicate on top of it.
        if let existing = window(showing: url) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = createWindow(for: url)
        let viewController = MarkdownViewController(fileURL: url)
        window.contentViewController = viewController

        // Size and center AFTER setting contentViewController —
        // NSWindow resizes itself to the content view's frame when
        // contentViewController is assigned, discarding the initial contentRect.
        let theme = ThemeManager.shared.currentTheme
        window.setContentSize(WindowSizer.defaultSize(for: theme))
        centerWindowOnCursorDisplay(window)

        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    func openFromClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string), !string.isEmpty else {
            NSSound.beep()
            return
        }
        openSource(string, title: "Clipboard")
    }

    /// Markdown piped to the `mrkd` command. It is titled "stdin" for the same
    /// reason clipboard windows are titled "Clipboard": the title names where
    /// the text came from, which is the only true thing about a document with
    /// no file behind it.
    func openStandardInput(source: String) {
        openSource(source, title: "stdin")
    }

    /// Reopens the newest document that is still on disk. Returns false when
    /// there is nothing left to reopen.
    @discardableResult
    func restoreMostRecentDocument() -> Bool {
        guard let url = RecentDocuments.mostRecent(
            from: NSDocumentController.shared.recentDocumentURLs,
            isOpenable: RecentDocuments.isOpenableFile
        ) else { return false }

        openFile(url)
        return true
    }

    /// Markdown with no file behind it — the clipboard, or standard input.
    private func openSource(_ string: String, title: String) {
        let window = createSourceWindow(titled: title)
        let viewController = MarkdownViewController(markdownString: string)
        window.contentViewController = viewController

        let theme = ThemeManager.shared.currentTheme
        window.setContentSize(WindowSizer.defaultSize(for: theme))
        centerWindowOnCursorDisplay(window)

        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    // MARK: - Window Creation

    private func createSourceWindow(titled title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        window.title = title
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed

        let theme = ThemeManager.shared.currentTheme
        window.minSize = WindowSizer.minimumSize(for: theme)
        window.delegate = self

        return window
    }

    // MARK: - Window Creation (File)

    private func createWindow(for url: URL) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        window.title = url.lastPathComponent
        window.representedURL = url
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed

        let theme = ThemeManager.shared.currentTheme
        window.minSize = WindowSizer.minimumSize(for: theme)
        window.delegate = self

        return window
    }

    private func window(showing url: URL) -> NSWindow? {
        let key = DocumentIdentity.key(for: url)
        return windows.first { window in
            guard let represented = window.representedURL else { return false }
            return DocumentIdentity.key(for: represented) == key
        }
    }

    private func centerWindowOnCursorDisplay(_ window: NSWindow) {
        // Get mouse location in screen coordinates
        let mouseLocation = NSEvent.mouseLocation

        // Find the screen containing the mouse cursor
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]

        // Center the window on the target screen
        let screenFrame = targetScreen.visibleFrame
        let windowFrame = window.frame

        let centeredX = screenFrame.midX - windowFrame.width / 2
        let centeredY = screenFrame.midY - windowFrame.height / 2

        window.setFrameOrigin(NSPoint(x: centeredX, y: centeredY))
    }

    private func updateWindowMinSizes() {
        let theme = ThemeManager.shared.currentTheme
        let minSize = WindowSizer.minimumSize(for: theme)
        for window in windows {
            window.minSize = minSize
        }
    }
}

// MARK: - NSWindowDelegate

extension WindowManager: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
    }
}
