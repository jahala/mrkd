import AppKit

/// The parts the Settings window is built from, laid out the way macOS System
/// Settings is: a section title, then a rounded group of rows, each with its
/// label on the left and its control on the right, and an optional short note
/// under the group.
enum SettingsForm {

    /// The width of everything below the theme picker.
    static let contentWidth: CGFloat = 560

    static func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    /// A note under a group, hidden until it has something to say.
    static func note() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.isSelectable = true
        label.preferredMaxLayoutWidth = contentWidth
        label.isHidden = true
        return label
    }

    /// One row: the title (and an optional line under it) on the left, the
    /// controls on the right.
    static func row(title: String, subtitle: String? = nil, controls: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        var labels: [NSView] = [titleLabel]
        if let subtitle {
            let line = NSTextField(labelWithString: subtitle)
            line.font = .systemFont(ofSize: 11)
            line.textColor = .secondaryLabelColor
            labels.append(line)
        }
        let left = NSStackView(views: labels)
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 2

        let right = NSStackView(views: controls)
        right.spacing = 10
        right.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let row = NSStackView(views: [left, spacer, right])
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return row
    }

    /// Rows in a rounded group, with a hairline between them.
    static func group(_ rows: [NSView]) -> NSView {
        var views: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = NSBox()
                line.boxType = .separator
                views.append(line)
            }
            views.append(row)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let box = SettingsGroupView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            box.widthAnchor.constraint(equalToConstant: contentWidth),
        ])
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return box
    }
}

/// The rounded background of a group. Drawn rather than layer-backed, so
/// its colours follow light and dark appearance by themselves.
final class SettingsGroupView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        (dark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 1, alpha: 0.7)).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// A status in a row: a coloured dot and a word or two. Green when all is
/// well, orange when the user is needed, no dot otherwise.
final class SettingsStatusView: NSStackView {

    private let dot = StatusDot()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
        setViews([dot, label], in: .leading)
        spacing = 6
        alignment = .centerY
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ text: String, tone: SettingsStatus.Tone, details: String? = nil) {
        label.stringValue = text
        toolTip = details
        switch tone {
        case .good:
            dot.color = .systemGreen
            dot.isHidden = false
        case .attention:
            dot.color = .systemOrange
            dot.isHidden = false
        case .neutral:
            dot.isHidden = true
        }
        setAccessibilityLabel(text)
    }

    private final class StatusDot: NSView {
        var color: NSColor = .systemGreen {
            didSet { needsDisplay = true }
        }

        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
    }
}
