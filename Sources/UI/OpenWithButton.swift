import AppKit

final class OpenWithButton: NSView {

    private let button: NSButton
    private let fileURL: URL
    private var themeObserver: NSObjectProtocol?
    private var isHovered = false

    private var currentTheme: Theme { ThemeManager.shared.currentTheme }

    init(fileURL: URL) {
        self.fileURL = fileURL

        button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.title = "Open"
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Open")
        button.imagePosition = .imageTrailing
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        super.init(frame: .zero)

        setupViews()
        applyTheme()

        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.themeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyTheme()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(buttonClicked)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 26)
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        setAccessibilityRole(.button)
        setAccessibilityLabel("Open")
        setAccessibilityHelp("Opens this file in another application")
        focusRingType = .exterior
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyTheme()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyTheme()
    }

    private func applyTheme() {
        let theme = currentTheme
        let bgColor: NSColor = isHovered
            ? theme.accentColor.withAlphaComponent(0.15)
            : theme.codeBackgroundColor
        let borderColor: NSColor = isHovered
            ? theme.accentColor.withAlphaComponent(0.5)
            : theme.blockquoteBarColor
        let tint: NSColor = isHovered ? theme.accentColor : theme.textColor

        layer?.backgroundColor = bgColor.cgColor
        layer?.borderColor = borderColor.cgColor
        button.contentTintColor = tint
    }

    // MARK: - Button Action

    @objc private func buttonClicked() {
        let menu = NSMenu()

        // Get applications that can open this file, excluding this app
        let ownBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            .filter { $0.standardizedFileURL != ownBundleURL }

        if apps.isEmpty {
            let item = NSMenuItem(title: "No applications available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let iconSize = NSSize(width: 16, height: 16)
            for appURL in apps {
                let appName = appURL.deletingPathExtension().lastPathComponent
                let item = NSMenuItem(title: appName, action: #selector(openWithApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = appURL
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = iconSize
                item.image = icon
                menu.addItem(item)
            }
        }

        // Show menu below the button
        let location = NSPoint(x: bounds.minX, y: bounds.minY)
        menu.popUp(positioning: nil, at: location, in: self)
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.showError(error)
                }
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to open file"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
