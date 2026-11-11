import AppKit
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController {

    // MARK: - Singleton

    static let shared = SettingsWindowController()

    // MARK: - UI Components

    private let contentView = NSView()
    private var themePickerGrid: ThemePickerGridView!
    private var bodyFontPopUpButton: NSPopUpButton!
    private var bodyFontSizePopUpButton: NSPopUpButton!
    private var readingWidthPopUpButton: NSPopUpButton!
    private var codeFontPopUpButton: NSPopUpButton!
    private var pageStack: NSStackView!
    private let commandLineStatus = SettingsStatusView()
    private var commandLineButton: NSButton!
    private var commandLineGroup: NSView!
    private let commandLineNote = SettingsForm.note()
    private let quickLookStatus = SettingsStatusView()
    private var quickLookActionButton: NSButton!
    private var quickLookSwitch: NSSwitch!
    private var quickLookGroup: NSView!
    private let quickLookNote = SettingsForm.note()

    /// The last check's answer, which the Fix button acts on.
    private var quickLookReport: QuickLookReport?
    private var quickLookRequest = 0
    /// While a repair runs, reopening Settings does not start a second check:
    /// it would read the registrations half-changed and replace the repair's
    /// own result, including any failure, before the user saw it.
    private var quickLookRepairRunning = false

    /// Starts unknown: a GUI app inherits launchd's PATH, not the user's, so
    /// the real answer has to be fetched from the login shell.
    private var shellPathState: ShellPathState = .unknown
    private var didProbeShellPath = false

    private static let bodyFontSizes: [Int] = [11, 12, 13, 14, 15, 16, 17, 18, 20]

    private static let monospaceFonts = [
        "SF Mono", "Menlo", "Fira Code", "JetBrains Mono", "Geist Mono", "Source Code Pro", "IBM Plex Mono",
        "iA Writer Mono V"
    ]

    private static let proportionalFonts = [
        "Geist", "Inter", "Open Sans", "Source Sans 3", "Literata", "Merriweather"
    ]

    // MARK: - Initialization

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.title = "Settings"
        window.contentView = contentView
        window.isReleasedWhenClosed = false

        setupUI()
        observeThemeChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        pageStack = stackView

        themePickerGrid = ThemePickerGridView(selectedTheme: ThemeManager.shared.selectedThemeName)
        themePickerGrid.translatesAutoresizingMaskIntoConstraints = false
        themePickerGrid.onImportTheme = { [weak self] in
            self?.importTheme()
        }

        let textGroup = SettingsForm.group([
            SettingsForm.row(title: "Body font", controls: [fontPopUp(
                families: Self.monospaceFonts + Self.proportionalFonts,
                currentFamily: ThemeManager.shared.fontFamily,
                action: #selector(bodyFontChanged(_:)),
                assignTo: &bodyFontPopUpButton
            )]),
            SettingsForm.row(title: "Font size", controls: [fontSizePopUp()]),
            SettingsForm.row(title: "Reading width", controls: [readingWidthPopUp()]),
            SettingsForm.row(title: "Code font", controls: [fontPopUp(
                families: Self.monospaceFonts,
                currentFamily: ThemeManager.shared.codeFontFamily,
                action: #selector(codeFontChanged(_:)),
                assignTo: &codeFontPopUpButton
            )]),
        ])

        commandLineGroup = createCommandLineGroup()
        quickLookGroup = createQuickLookGroup()

        let sections: [[NSView]] = [
            [SettingsForm.sectionTitle("Theme"), themePickerGrid],
            [SettingsForm.sectionTitle("Text"), textGroup],
            [SettingsForm.sectionTitle("Command Line"), commandLineGroup, commandLineNote],
            [SettingsForm.sectionTitle("Quick Look"), quickLookGroup, quickLookNote],
        ]
        for section in sections {
            for view in section {
                stackView.addArrangedSubview(view)
            }
            // More space between sections than within them.
            if let last = section.last {
                stackView.setCustomSpacing(24, after: last)
            }
        }
        stackView.setCustomSpacing(24, after: themePickerGrid)
        stackView.setCustomSpacing(24, after: textGroup)
        updateNoteSpacing()

        // Wrap in a scroll view so all content is reachable
        let scrollView = NSScrollView()
        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])

        window?.makeFirstResponder(themePickerGrid)
    }

    private func fontPopUp(
        families: [String],
        currentFamily: String,
        action: Selector,
        assignTo button: inout NSPopUpButton!
    ) -> NSPopUpButton {
        let popUpButton = NSPopUpButton()
        popUpButton.target = self
        popUpButton.action = action
        button = popUpButton

        let installedFamilies = NSFontManager.shared.availableFontFamilies

        for family in families {
            if installedFamilies.contains(family) {
                let menuItem = NSMenuItem(title: family, action: nil, keyEquivalent: "")
                if let font = NSFont(name: family, size: 13) {
                    menuItem.attributedTitle = NSAttributedString(string: family, attributes: [.font: font])
                }
                popUpButton.menu?.addItem(menuItem)
                if family == currentFamily {
                    popUpButton.select(menuItem)
                }
            }
        }

        // Add current family if not in predefined list
        if !families.contains(currentFamily) && installedFamilies.contains(currentFamily) {
            let menuItem = NSMenuItem(title: currentFamily, action: nil, keyEquivalent: "")
            if let font = NSFont(name: currentFamily, size: 13) {
                menuItem.attributedTitle = NSAttributedString(string: currentFamily, attributes: [.font: font])
            }
            popUpButton.menu?.addItem(menuItem)
            popUpButton.selectItem(withTitle: currentFamily)
        }

        return popUpButton
    }

    private func fontSizePopUp() -> NSPopUpButton {
        let popUpButton = NSPopUpButton()
        popUpButton.target = self
        popUpButton.action = #selector(bodyFontSizeChanged(_:))
        bodyFontSizePopUpButton = popUpButton

        let current = Int(ThemeManager.shared.fontSize.rounded())
        for size in Self.bodyFontSizes {
            let menuItem = NSMenuItem(title: "\(size) pt", action: nil, keyEquivalent: "")
            menuItem.representedObject = size
            popUpButton.menu?.addItem(menuItem)
            if size == current {
                popUpButton.select(menuItem)
            }
        }

        // Surface a non-preset size (e.g. result of repeated ⌘+ / ⌘-)
        // so the user can see what's active and re-select it.
        if !Self.bodyFontSizes.contains(current) {
            let menuItem = NSMenuItem(title: "\(current) pt", action: nil, keyEquivalent: "")
            menuItem.representedObject = current
            popUpButton.menu?.addItem(menuItem)
            popUpButton.select(menuItem)
        }

        return popUpButton
    }

    private func readingWidthPopUp() -> NSPopUpButton {
        let popUpButton = NSPopUpButton()
        popUpButton.target = self
        popUpButton.action = #selector(readingWidthChanged(_:))
        readingWidthPopUpButton = popUpButton

        let current = ThemeManager.shared.readingWidth
        for width in ReadingWidth.allCases {
            let menuItem = NSMenuItem(title: width.title, action: nil, keyEquivalent: "")
            menuItem.representedObject = width.rawValue
            popUpButton.menu?.addItem(menuItem)
            if width == current {
                popUpButton.select(menuItem)
            }
        }

        return popUpButton
    }

    /// A group sits 6 points above its note when the note shows, and a
    /// section's width above the next title when it doesn't.
    private func updateNoteSpacing() {
        guard let pageStack else { return }
        for (group, note) in [(commandLineGroup, commandLineNote), (quickLookGroup, quickLookNote)] {
            // A status can arrive while the window is still being built,
            // before its group is on the page.
            guard let group, pageStack.arrangedSubviews.contains(group) else { continue }
            pageStack.setCustomSpacing(note.isHidden ? 24 : 6, after: group)
        }
    }

    // MARK: - Command Line

    private func createCommandLineGroup() -> NSView {
        let button = NSButton(title: "Install", target: self, action: #selector(installCommandLineTool(_:)))
        button.bezelStyle = .rounded
        button.isHidden = true
        commandLineButton = button

        let group = SettingsForm.group([
            SettingsForm.row(
                title: "mrkd command",
                subtitle: "Open Markdown from Terminal with mrkd FILE.",
                controls: [commandLineStatus, button]
            ),
        ])
        commandLineGroup = group
        refreshCommandLineStatus()
        return group
    }

    private var commandLineDestination: URL {
        CommandLineLauncher.installURL(homeDirectory: URL(fileURLWithPath: NSHomeDirectory()))
    }

    /// The script that *would* be installed for this copy of the app — the same
    /// value drives the status text and the install itself.
    private var commandLineScript: String? {
        guard let executable = Bundle.main.executableURL else { return nil }
        return CommandLineLauncher.script(appExecutable: executable)
    }

    private func refreshCommandLineStatus() {
        guard let script = commandLineScript else {
            commandLineStatus.show(
                "Unavailable", tone: .attention,
                details: "mrkd cannot locate its own executable, so the command cannot be installed."
            )
            commandLineButton.isHidden = true
            show(nil, in: commandLineNote)
            return
        }

        let destination = commandLineDestination
        let status = LauncherInstaller.status(
            existing: LauncherInstallation.existingEntry(at: destination),
            desired: script
        )
        let displayPath = CommandLineLauncher.displayPath(
            destination,
            homeDirectory: URL(fileURLWithPath: NSHomeDirectory())
        )
        let row = LauncherInstaller.settingsStatus(status: status, displayPath: displayPath, pathState: shellPathState)
        commandLineStatus.show(
            row.text, tone: row.tone,
            details: LauncherInstaller.statusText(status: status, displayPath: displayPath, pathState: shellPathState)
        )
        commandLineButton.title = row.action ?? ""
        commandLineButton.isHidden = row.action == nil
        show(row.note, in: commandLineNote)
    }

    private func show(_ text: String?, in note: NSTextField) {
        note.stringValue = text ?? ""
        note.isHidden = text == nil
        updateNoteSpacing()
    }

    @objc private func installCommandLineTool(_ sender: NSButton) {
        guard let script = commandLineScript else { return }
        let destination = commandLineDestination
        let displayPath = CommandLineLauncher.displayPath(
            destination,
            homeDirectory: URL(fileURLWithPath: NSHomeDirectory())
        )

        do {
            let decision = try LauncherInstallation.install(script: script, at: destination)
            if decision == .refused {
                let alert = NSAlert()
                alert.messageText = "Something else is already at \(displayPath)"
                alert.informativeText = "mrkd left it alone. Move that file aside and install again."
                alert.runModal()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t install the mrkd command"
            alert.runModal()
        }

        // The user may have just fixed their PATH; ask the shell again.
        didProbeShellPath = false
        probeShellPathIfNeeded()
        refreshCommandLineStatus()
    }

    private func probeShellPathIfNeeded() {
        guard !didProbeShellPath else { return }
        didProbeShellPath = true

        let home = URL(fileURLWithPath: NSHomeDirectory())
        let directory = CommandLineLauncher.installURL(homeDirectory: home).deletingLastPathComponent()

        Task.detached(priority: .utility) {
            let state: ShellPathState
            if let path = LoginShellPath.read() {
                state = ShellPath.contains(directory, in: path, homeDirectory: home) ? .onPath : .missing
            } else {
                state = .unknown
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.shellPathState = state
                self.refreshCommandLineStatus()
            }
        }
    }

    // MARK: - Quick Look

    private func createQuickLookGroup() -> NSView {
        quickLookStatus.show("Checking…", tone: .neutral)

        let button = NSButton(title: "Fix", target: self, action: #selector(repairQuickLook(_:)))
        button.bezelStyle = .rounded
        button.isHidden = true
        quickLookActionButton = button

        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = #selector(quickLookCheckAtLaunchChanged(_:))
        toggle.setAccessibilityLabel("Check when mrkd starts")
        quickLookSwitch = toggle

        let group = SettingsForm.group([
            SettingsForm.row(title: "Finder previews", controls: [quickLookStatus, button]),
            SettingsForm.row(title: "Check when mrkd starts", controls: [toggle]),
        ])
        quickLookGroup = group
        refreshQuickLookCheckbox()
        return group
    }

    private var appURL: URL { Bundle.main.bundleURL }

    private func refreshQuickLookCheckbox() {
        quickLookSwitch.state = QuickLookCheckPreferences(defaults: .standard).checksAtLaunch ? .on : .off
    }

    /// Runs the check off the main thread and shows the answer. Each request
    /// is numbered and only the newest one's answer is shown, so a slow check
    /// cannot overwrite the result of a repair that finished after it.
    private func refreshQuickLookStatus(repair steps: [QuickLookStep]? = nil) {
        guard !quickLookRepairRunning else { return }
        quickLookRequest += 1
        let request = quickLookRequest
        let appURL = appURL

        quickLookActionButton.isEnabled = false
        if steps != nil {
            quickLookRepairRunning = true
            quickLookStatus.show("Fixing…", tone: .neutral)
        }

        Task.detached(priority: .userInitiated) {
            let failure = steps.flatMap { QuickLookMaintenance.perform($0) }
            let report = QuickLookMaintenance.check(appURL: appURL)
            await MainActor.run { [weak self] in
                guard let self, request == self.quickLookRequest else { return }
                self.quickLookRepairRunning = false
                self.showQuickLook(report, repairFailure: failure)
            }
        }
    }

    private func showQuickLook(_ report: QuickLookReport, repairFailure: String?) {
        quickLookReport = report

        // The row stays short. The full explanation is one hover away.
        var details = QuickLookCheck.statusText(report, homeDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        let row = QuickLookCheck.settingsStatus(report)
        if let repairFailure {
            details = "The fix did not finish. \(repairFailure).\n\n" + details
            quickLookStatus.show("Fix didn’t work", tone: .attention, details: details)
        } else {
            quickLookStatus.show(row.text, tone: row.tone, details: details)
        }
        show(row.note, in: quickLookNote)

        if let title = row.action {
            quickLookActionButton.title = title
            quickLookActionButton.isHidden = false
            quickLookActionButton.isEnabled = true
        } else {
            quickLookActionButton.isHidden = true
        }
    }

    @objc private func repairQuickLook(_ sender: NSButton) {
        guard let report = quickLookReport else { return }
        refreshQuickLookStatus(repair: QuickLookCheck.repairSteps(for: report, appPath: appURL.path))
    }

    @objc private func quickLookCheckAtLaunchChanged(_ sender: NSSwitch) {
        QuickLookCheckPreferences(defaults: .standard).checksAtLaunch = sender.state == .on
    }

    // MARK: - Actions

    @objc private func bodyFontChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.selectedItem?.title else { return }
        ThemeManager.shared.fontFamily = selectedTitle
    }

    @objc private func bodyFontSizeChanged(_ sender: NSPopUpButton) {
        guard let size = sender.selectedItem?.representedObject as? Int else { return }
        ThemeManager.shared.fontSize = CGFloat(size)
    }

    @objc private func codeFontChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.selectedItem?.title else { return }
        ThemeManager.shared.codeFontFamily = selectedTitle
    }

    @objc private func readingWidthChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let width = ReadingWidth(rawValue: rawValue) else { return }
        ThemeManager.shared.readingWidth = width
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "itermcolors"),
            UTType(filenameExtension: "json"),
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an iTerm2 or VS Code theme file"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let _ = try ThemeManager.shared.importTheme(from: url)
            // Theme is auto-selected by importTheme, which triggers notification.
            // Recreate the grid to show the new theme card.
            rebuildThemeGrid()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func rebuildThemeGrid() {
        let stackView = themePickerGrid.superview as? NSStackView
        let gridIndex = stackView?.arrangedSubviews.firstIndex(of: themePickerGrid)

        themePickerGrid.removeFromSuperview()

        let newGrid = ThemePickerGridView(selectedTheme: ThemeManager.shared.selectedThemeName)
        newGrid.translatesAutoresizingMaskIntoConstraints = false
        newGrid.onImportTheme = { [weak self] in
            self?.importTheme()
        }
        themePickerGrid = newGrid

        if let stackView = stackView, let index = gridIndex {
            stackView.insertArrangedSubview(newGrid, at: index)
        }

        window?.makeFirstResponder(themePickerGrid)
    }

    // MARK: - Theme Observation

    private var themeObserver: NSObjectProtocol?

    private func observeThemeChanges() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.themeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateUIForCurrentTheme()
            }
        }
    }

    private func updateUIForCurrentTheme() {
        themePickerGrid.updateSelection(to: ThemeManager.shared.selectedThemeName)

        let currentFamily = ThemeManager.shared.fontFamily
        if bodyFontPopUpButton.selectedItem?.title != currentFamily {
            bodyFontPopUpButton.selectItem(withTitle: currentFamily)
        }

        let currentCodeFamily = ThemeManager.shared.codeFontFamily
        if codeFontPopUpButton.selectedItem?.title != currentCodeFamily {
            codeFontPopUpButton.selectItem(withTitle: currentCodeFamily)
        }

        let currentSize = Int(ThemeManager.shared.fontSize.rounded())
        let currentMenuSize = bodyFontSizePopUpButton.selectedItem?.representedObject as? Int
        if currentMenuSize != currentSize {
            if let match = bodyFontSizePopUpButton.itemArray.first(where: {
                ($0.representedObject as? Int) == currentSize
            }) {
                bodyFontSizePopUpButton.select(match)
            } else {
                let menuItem = NSMenuItem(title: "\(currentSize) pt", action: nil, keyEquivalent: "")
                menuItem.representedObject = currentSize
                bodyFontSizePopUpButton.menu?.addItem(menuItem)
                bodyFontSizePopUpButton.select(menuItem)
            }
        }

        let currentWidth = ThemeManager.shared.readingWidth.rawValue
        if readingWidthPopUpButton.selectedItem?.representedObject as? String != currentWidth,
           let match = readingWidthPopUpButton.itemArray.first(where: {
               ($0.representedObject as? String) == currentWidth
           }) {
            readingWidthPopUpButton.select(match)
        }
    }

    // MARK: - Window Management

    override func showWindow(_ sender: Any?) {
        if let frontWindow = NSApp.windows.first(where: { $0.isVisible && $0 !== window }) {
            window?.center()
            window?.setFrameOrigin(NSPoint(
                x: frontWindow.frame.midX - (window?.frame.width ?? 0) / 2,
                y: frontWindow.frame.midY - (window?.frame.height ?? 0) / 2
            ))
        } else {
            window?.center()
        }

        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.makeFirstResponder(themePickerGrid)

        refreshCommandLineStatus()
        probeShellPathIfNeeded()
        refreshQuickLookCheckbox()
        refreshQuickLookStatus()
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
