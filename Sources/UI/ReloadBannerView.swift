import AppKit

/// Tells the reader their file is gone.
///
/// External *edits* need no banner — they reload themselves — so deletion is
/// the only thing left worth interrupting for, and the only thing there is
/// nothing sensible to render for.
final class ReloadBannerView: NSView {

    var onDismiss: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
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

        dismissButton.bezelStyle = .rounded
        dismissButton.controlSize = .small
        dismissButton.isBordered = false
        dismissButton.target = self
        dismissButton.action = #selector(dismissTapped)

        let stack = NSStackView(views: [label, dismissButton])
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
        setAccessibilityLabel("File deleted notification")
        dismissButton.setAccessibilityLabel("Dismiss notification")
    }

    func showDeletionMessage(path: String) {
        label.stringValue = "File has been deleted: \(path)"
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
