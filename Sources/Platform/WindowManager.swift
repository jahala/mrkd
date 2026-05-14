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

    func openFile(_ url: URL) {
        // Record this file for Open Recent menu
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

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

        let window = createClipboardWindow()
        let viewController = MarkdownViewController(markdownString: string)
        window.contentViewController = viewController

        let theme = ThemeManager.shared.currentTheme
        window.setContentSize(WindowSizer.defaultSize(for: theme))
        centerWindowOnCursorDisplay(window)

        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    // MARK: - Window Creation

    private func createClipboardWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        window.title = "Clipboard"
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
