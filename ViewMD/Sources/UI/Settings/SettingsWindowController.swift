import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {

    // MARK: - Singleton

    static let shared = SettingsWindowController()

    // MARK: - UI Components

    private let contentView = NSView()
    private var themePickerGrid: ThemePickerGridView!
    private var bodyFontPopUpButton: NSPopUpButton!
    private var codeFontPopUpButton: NSPopUpButton!

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

        let themeSectionLabel = NSTextField(labelWithString: "Theme")
        themeSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        themeSectionLabel.translatesAutoresizingMaskIntoConstraints = false

        themePickerGrid = ThemePickerGridView(selectedTheme: ThemeManager.shared.selectedThemeName)
        themePickerGrid.translatesAutoresizingMaskIntoConstraints = false

        let bodyFontRow = createFontRow(
            label: "Body Font",
            families: Self.monospaceFonts + Self.proportionalFonts,
            currentFamily: ThemeManager.shared.fontFamily,
            action: #selector(bodyFontChanged(_:)),
            assignTo: &bodyFontPopUpButton
        )

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
        stackView.addArrangedSubview(codeFontRow)

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
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

    // MARK: - Actions

    @objc private func bodyFontChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.selectedItem?.title else { return }
        ThemeManager.shared.fontFamily = selectedTitle
    }

    @objc private func codeFontChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.selectedItem?.title else { return }
        ThemeManager.shared.codeFontFamily = selectedTitle
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
        let currentFamily = ThemeManager.shared.fontFamily
        if bodyFontPopUpButton.selectedItem?.title != currentFamily {
            bodyFontPopUpButton.selectItem(withTitle: currentFamily)
        }

        let currentCodeFamily = ThemeManager.shared.codeFontFamily
        if codeFontPopUpButton.selectedItem?.title != currentCodeFamily {
            codeFontPopUpButton.selectItem(withTitle: currentCodeFamily)
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
