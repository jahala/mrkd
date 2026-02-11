import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {

    // MARK: - Singleton

    static let shared = SettingsWindowController()

    // MARK: - UI Components

    private let contentView = NSView()
    private var themePickerGrid: ThemePickerGridView!
    private var fontPopUpButton: NSPopUpButton!

    private let availableFontFamilies = ["SF Mono", "Menlo", "Fira Code", "JetBrains Mono", "IBM Plex Mono"]

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
        window.isReleasedWhenClosed = false // Keep window in memory

        setupUI()
        observeThemeChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        // Create a vertical stack manually
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Theme section header
        let themeSectionLabel = NSTextField(labelWithString: "Theme")
        themeSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        themeSectionLabel.translatesAutoresizingMaskIntoConstraints = false

        // Theme picker grid
        themePickerGrid = ThemePickerGridView(selectedTheme: ThemeManager.shared.selectedThemeName)
        themePickerGrid.translatesAutoresizingMaskIntoConstraints = false

        // Font section
        let fontSectionView = createFontSectionView()
        fontSectionView.translatesAutoresizingMaskIntoConstraints = false

        // Add to stack
        stackView.addArrangedSubview(themeSectionLabel)
        stackView.addArrangedSubview(themePickerGrid)
        stackView.addArrangedSubview(fontSectionView)

        contentView.addSubview(stackView)

        // Layout constraints
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        ])

        // Set initial keyboard focus to theme grid
        window?.makeFirstResponder(themePickerGrid)
    }

    private func createFontSectionView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Font label
        let fontLabel = NSTextField(labelWithString: "Font")
        fontLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        fontLabel.translatesAutoresizingMaskIntoConstraints = false

        // Font popup button
        fontPopUpButton = NSPopUpButton()
        fontPopUpButton.translatesAutoresizingMaskIntoConstraints = false
        fontPopUpButton.target = self
        fontPopUpButton.action = #selector(fontFamilyChanged(_:))

        // Populate font menu with only installed fonts
        let installedFamilies = NSFontManager.shared.availableFontFamilies
        let currentFamily = ThemeManager.shared.fontFamily

        for family in availableFontFamilies {
            if installedFamilies.contains(family) {
                let menuItem = NSMenuItem(title: family, action: nil, keyEquivalent: "")

                // Render menu item in its own font
                if let font = NSFont(name: family, size: 13) {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font
                    ]
                    menuItem.attributedTitle = NSAttributedString(string: family, attributes: attributes)
                }

                fontPopUpButton.menu?.addItem(menuItem)

                // Select current font
                if family == currentFamily {
                    fontPopUpButton.select(menuItem)
                }
            }
        }

        // If current family is not in our list but is installed, add it
        if !availableFontFamilies.contains(currentFamily) && installedFamilies.contains(currentFamily) {
            let menuItem = NSMenuItem(title: currentFamily, action: nil, keyEquivalent: "")
            if let font = NSFont(name: currentFamily, size: 13) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font
                ]
                menuItem.attributedTitle = NSAttributedString(string: currentFamily, attributes: attributes)
            }
            fontPopUpButton.menu?.addItem(menuItem)
            fontPopUpButton.selectItem(withTitle: currentFamily)
        }

        container.addSubview(fontLabel)
        container.addSubview(fontPopUpButton)

        NSLayoutConstraint.activate([
            fontLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            fontLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            fontPopUpButton.leadingAnchor.constraint(equalTo: fontLabel.trailingAnchor, constant: 12),
            fontPopUpButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            fontPopUpButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            fontPopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            container.heightAnchor.constraint(equalTo: fontPopUpButton.heightAnchor)
        ])

        return container
    }

    // MARK: - Actions

    @objc private func fontFamilyChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.selectedItem?.title else { return }
        ThemeManager.shared.fontFamily = selectedTitle
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
                // Update UI if needed when theme changes from elsewhere
                // (e.g., if theme changed via menu while settings window is open)
                self?.updateUIForCurrentTheme()
            }
        }
    }

    private func updateUIForCurrentTheme() {
        // Update font selector if fontFamily changed externally
        let currentFamily = ThemeManager.shared.fontFamily
        if fontPopUpButton.selectedItem?.title != currentFamily {
            fontPopUpButton.selectItem(withTitle: currentFamily)
        }

        // The theme grid updates itself via ThemeManager notifications
    }

    // MARK: - Window Management

    override func showWindow(_ sender: Any?) {
        // Center relative to frontmost viewer window if available
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

        // Set initial focus to theme grid
        window?.makeFirstResponder(themePickerGrid)
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
