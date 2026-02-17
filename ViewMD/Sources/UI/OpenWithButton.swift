import AppKit

final class OpenWithButton: NSView {

    private let visualEffectView: NSVisualEffectView
    private let button: NSButton
    private let fileURL: URL

    private var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init(fileURL: URL) {
        self.fileURL = fileURL

        // Create visual effect view for blur background
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 3

        // Create button with SF Symbol and title
        button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.title = "Open"
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Open")
        button.imagePosition = .imageTrailing
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = .secondaryLabelColor

        super.init(frame: .zero)

        setupViews()
        updateTransparencySettings()
        observeAccessibilityChanges()
        alphaValue = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupViews() {
        wantsLayer = true

        // Add visual effect view
        addSubview(visualEffectView)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        // Add button to visual effect view
        visualEffectView.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(buttonClicked)

        NSLayoutConstraint.activate([
            // Visual effect view fills the container
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Button with horizontal padding
            button.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            button.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),

            // Container height
            heightAnchor.constraint(equalToConstant: 24)
        ])

        // Accessibility
        setAccessibilityRole(.button)
        setAccessibilityLabel("Open")
        setAccessibilityHelp("Opens this file in another application")
        focusRingType = .exterior
    }

    private func observeAccessibilityChanges() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateTransparencySettings()
            }
        }
    }

    private func updateTransparencySettings() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            visualEffectView.state = .inactive
            visualEffectView.material = .windowBackground
            wantsLayer = true
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        } else {
            visualEffectView.state = .active
            visualEffectView.material = .hudWindow
            layer?.backgroundColor = nil
        }
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
