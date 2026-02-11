import AppKit

final class OpenWithButton: NSView {

    private let visualEffectView: NSVisualEffectView
    private let button: NSButton
    private let fileURL: URL

    private var fadeTimer: Timer?
    private var isVisible = false
    private let fadeInDuration: TimeInterval = 0.2
    private let fadeOutDelay: TimeInterval = 2.0

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
        visualEffectView.layer?.cornerRadius = 8

        // Create button with SF Symbol
        button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Open With")
        button.imagePosition = .imageOnly
        button.contentTintColor = .controlTextColor

        super.init(frame: .zero)

        setupViews()
        updateTransparencySettings()
        observeAccessibilityChanges()
        alphaValue = 0 // Start hidden
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

            // Button centered in visual effect view with padding
            button.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),

            // Container size
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 44)
        ])

        // Accessibility
        setAccessibilityRole(.button)
        setAccessibilityLabel("Open With")
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

    // MARK: - Visibility

    func show() {
        guard !isVisible else { return }
        isVisible = true

        fadeTimer?.invalidate()

        if reduceMotionEnabled {
            alphaValue = 1.0
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeInDuration
                context.allowsImplicitAnimation = true
                animator().alphaValue = 1.0
            }
        }

        // Schedule fade out
        scheduleFadeOut()
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        isVisible = false

        fadeTimer?.invalidate()

        if reduceMotionEnabled || !animated {
            alphaValue = 0.0
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeInDuration
                context.allowsImplicitAnimation = true
                animator().alphaValue = 0.0
            }
        }
    }

    private func scheduleFadeOut() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: fadeOutDelay, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func resetFadeOutTimer() {
        if isVisible {
            scheduleFadeOut()
        }
    }

    // MARK: - Button Action

    @objc private func buttonClicked() {
        let menu = NSMenu()

        // Get applications that can open this file
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)

        if apps.isEmpty {
            let item = NSMenuItem(title: "No applications available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for appURL in apps {
                let appName = appURL.deletingPathExtension().lastPathComponent
                let item = NSMenuItem(title: appName, action: #selector(openWithApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = appURL
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

        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.showError(error)
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
