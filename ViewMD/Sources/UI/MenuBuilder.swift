import AppKit

@MainActor
enum MenuBuilder {

    static func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // 1. App Menu
        mainMenu.addItem(buildAppMenu())

        // 2. File Menu
        mainMenu.addItem(buildFileMenu())

        // 3. Edit Menu
        mainMenu.addItem(buildEditMenu())

        // 4. View Menu
        mainMenu.addItem(buildViewMenu())

        // 5. Window Menu
        mainMenu.addItem(buildWindowMenu())

        // 6. Help Menu
        mainMenu.addItem(buildHelpMenu())

        return mainMenu
    }

    // MARK: - App Menu

    private static func buildAppMenu() -> NSMenuItem {
        let appMenu = NSMenu(title: "mrkd")

        // About mrkd
        appMenu.addItem(NSMenuItem(
            title: "About mrkd",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))

        appMenu.addItem(.separator())

        // Settings...
        appMenu.addItem(NSMenuItem(
            title: "Settings...",
            action: #selector(AppDelegate.showSettings(_:)),
            keyEquivalent: ","
        ))

        appMenu.addItem(.separator())

        // Hide mrkd
        appMenu.addItem(NSMenuItem(
            title: "Hide mrkd",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))

        // Hide Others
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)

        // Show All
        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))

        appMenu.addItem(.separator())

        // Quit mrkd
        appMenu.addItem(NSMenuItem(
            title: "Quit mrkd",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    // MARK: - File Menu

    private static func buildFileMenu() -> NSMenuItem {
        let fileMenu = NSMenu(title: "File")

        // Open...
        fileMenu.addItem(NSMenuItem(
            title: "Open...",
            action: #selector(AppDelegate.openDocument(_:)),
            keyEquivalent: "o"
        ))

        // Open Recent
        let recentMenu = NSMenu(title: "Open Recent")
        let clearItem = NSMenuItem(
            title: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        recentMenu.addItem(clearItem)

        let recentItem = NSMenuItem(
            title: "Open Recent",
            action: nil,
            keyEquivalent: ""
        )
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)

        fileMenu.addItem(.separator())

        // Close Window
        fileMenu.addItem(NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }

    // MARK: - Edit Menu

    private static func buildEditMenu() -> NSMenuItem {
        let editMenu = NSMenu(title: "Edit")

        // Copy
        editMenu.addItem(NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))

        // Select All
        editMenu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        return editMenuItem
    }

    // MARK: - View Menu

    private static func buildViewMenu() -> NSMenuItem {
        let viewMenu = NSMenu(title: "View")

        // Actual Size
        viewMenu.addItem(NSMenuItem(
            title: "Actual Size",
            action: #selector(MarkdownViewController.resetFontSize(_:)),
            keyEquivalent: "0"
        ))

        // Zoom In
        viewMenu.addItem(NSMenuItem(
            title: "Zoom In",
            action: #selector(MarkdownViewController.increaseFontSize(_:)),
            keyEquivalent: "="
        ))

        // Zoom Out
        viewMenu.addItem(NSMenuItem(
            title: "Zoom Out",
            action: #selector(MarkdownViewController.decreaseFontSize(_:)),
            keyEquivalent: "-"
        ))

        viewMenu.addItem(.separator())

        // Enter Full Screen
        let fullScreenItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }

    // MARK: - Window Menu

    private static func buildWindowMenu() -> NSMenuItem {
        let windowMenu = NSMenu(title: "Window")

        // Minimize
        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))

        // Zoom
        windowMenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))

        windowMenu.addItem(.separator())

        // Bring All to Front
        windowMenu.addItem(NSMenuItem(
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        ))

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu

        // Set as NSApp.windowsMenu
        NSApp.windowsMenu = windowMenu

        return windowMenuItem
    }

    // MARK: - Help Menu

    private static func buildHelpMenu() -> NSMenuItem {
        let helpMenu = NSMenu(title: "Help")

        // mrkd Help
        helpMenu.addItem(NSMenuItem(
            title: "mrkd Help",
            action: nil,
            keyEquivalent: ""
        ))

        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu

        // Set as NSApp.helpMenu
        NSApp.helpMenu = helpMenu

        return helpMenuItem
    }
}
