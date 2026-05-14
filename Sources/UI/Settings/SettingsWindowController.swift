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
    private var codeFontPopUpButton: NSPopUpButton!

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
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let themeSectionLabel = NSTextField(labelWithString: "Theme")
        themeSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        themeSectionLabel.translatesAutoresizingMaskIntoConstraints = false

        themePickerGrid = ThemePickerGridView(selectedTheme: ThemeManager.shared.selectedThemeName)
        themePickerGrid.translatesAutoresizingMaskIntoConstraints = false
        themePickerGrid.onImportTheme = { [weak self] in
            self?.importTheme()
        }

        let bodyFontRow = createFontRow(
            label: "Body Font",
            families: Self.monospaceFonts + Self.proportionalFonts,
            currentFamily: ThemeManager.shared.fontFamily,
            action: #selector(bodyFontChanged(_:)),
            assignTo: &bodyFontPopUpButton
        )

        let fontSizeRow = createFontSizeRow()

        let codeFontRow = createFontRow(
            label: "Code Font",
            families: Self.monospaceFonts,
            currentFamily: ThemeManager.shared.codeFontFamily,
            action: #selector(codeFontChanged(_:)),
            assignTo: &codeFontPopUpButton
        )

        stackView.addArrangedSubview(themeSectionLabel)
        stackView.addArrangedSubview(themePickerGrid)
        stackView.addArrangedSubview(bodyFontRow)
        stackView.addArrangedSubview(fontSizeRow)
        stackView.addArrangedSubview(codeFontRow)

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

    private func createFontRow(
        label: String,
        families: [String],
        currentFamily: String,
        action: Selector,
        assignTo button: inout NSPopUpButton!
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let fontLabel = NSTextField(labelWithString: label)
        fontLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        fontLabel.translatesAutoresizingMaskIntoConstraints = false

        let popUpButton = NSPopUpButton()
        popUpButton.translatesAutoresizingMaskIntoConstraints = false
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

        container.addSubview(fontLabel)
        container.addSubview(popUpButton)

        NSLayoutConstraint.activate([
            fontLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            fontLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            fontLabel.widthAnchor.constraint(equalToConstant: 80),

            popUpButton.leadingAnchor.constraint(equalTo: fontLabel.trailingAnchor, constant: 12),
            popUpButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            popUpButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            popUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            container.heightAnchor.constraint(equalTo: popUpButton.heightAnchor)
        ])

        return container
    }

    private func createFontSizeRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Font Size")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false

        let popUpButton = NSPopUpButton()
        popUpButton.translatesAutoresizingMaskIntoConstraints = false
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

        container.addSubview(label)
        container.addSubview(popUpButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 80),

            popUpButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            popUpButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            popUpButton.widthAnchor.constraint(equalToConstant: 90),

            container.heightAnchor.constraint(equalTo: popUpButton.heightAnchor)
        ])

        return container
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
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
