import AppKit

final class ReloadBannerView: NSView {

    var onReload: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let label = NSTextField(labelWithString: "File has been modified externally")
    private let reloadButton = NSButton(title: "Reload", target: nil, action: nil)
    private let dismissButton = NSButton(title: "Dismiss", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor

        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor

        reloadButton.bezelStyle = .rounded
        reloadButton.controlSize = .small
        reloadButton.target = self
        reloadButton.action = #selector(reloadTapped)

        dismissButton.bezelStyle = .rounded
        dismissButton.controlSize = .small
        dismissButton.isBordered = false
        dismissButton.target = self
        dismissButton.action = #selector(dismissTapped)

        let stack = NSStackView(views: [label, reloadButton, dismissButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 32),
        ])

        // Accessibility
        setAccessibilityRole(.group)
        setAccessibilityLabel("File changed notification")
        reloadButton.setAccessibilityLabel("Reload file")
        dismissButton.setAccessibilityLabel("Dismiss notification")
    }

    func showDeletionMessage(path: String) {
        label.stringValue = "File has been deleted: \(path)"
        reloadButton.isHidden = true
    }

    @objc private func reloadTapped() {
        onReload?()
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
