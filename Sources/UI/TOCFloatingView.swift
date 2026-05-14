import AppKit

final class TOCFloatingView: NSView {

    var entries: [TOCEntry] = [] {
        didSet { rebuildRows() }
    }

    var activeEntry: TOCEntry? {
        didSet {
            guard activeEntry != oldValue else { return }
            for (entry, row) in rows {
                row.isActive = (entry == activeEntry)
            }
        }
    }

    var onSelect: ((TOCEntry) -> Void)?

    private let headerLabel = NSTextField()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField()
    private var rows: [TOCEntry: TOCRowView] = [:]
    private var themeObserver: NSObjectProtocol?

    private var currentTheme: Theme { ThemeManager.shared.currentTheme }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupViews()
        applyTheme()
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.themeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyTheme()
            self?.rebuildRows()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupViews() {
        // No layer background. TOC floats transparently against the article;
        // colors come from the active theme.
        headerLabel.stringValue = "ON THIS PAGE"
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.kerning = 0.6
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        headerLabel.isEditable = false
        headerLabel.isSelectable = false
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.distribution = .fill

        // Flipped clip view so the row stack anchors to the visual TOP of the
        // scroll area. NSClipView is unflipped by default — without this,
        // a short row list (fewer entries than fill the height) sinks to the
        // bottom of the scrollView's empty space.
        let clipView = FlippedClipView()
        clipView.documentView = stackView
        clipView.drawsBackground = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        emptyLabel.stringValue = "No headings"
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            headerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        scrollView.isHidden = true
        emptyLabel.isHidden = false
    }

    private func applyTheme() {
        let theme = currentTheme
        // Header gets the muted theme color used for blockquote text — same
        // visual register as secondary/tertiary chrome.
        headerLabel.textColor = theme.blockquoteColor
        // Re-apply the header string so the kerning attributed-string picks up
        // the new color (kerning setter rebuilds the attributed value).
        headerLabel.kerning = 0.6
        emptyLabel.textColor = theme.blockquoteColor
    }

    private func rebuildRows() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()

        let isEmpty = entries.isEmpty
        scrollView.isHidden = isEmpty
        emptyLabel.isHidden = !isEmpty

        let theme = currentTheme
        for entry in entries {
            let row = TOCRowView(entry: entry, theme: theme) { [weak self] selected in
                self?.onSelect?(selected)
            }
            row.isActive = (activeEntry == entry)
            rows[entry] = row
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }
}

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class TOCRowView: NSView {

    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            updateAppearance()
        }
    }

    private let entry: TOCEntry
    private let theme: Theme
    private let onClick: (TOCEntry) -> Void

    private let titleField = NSTextField()
    private let stripeLayer = CALayer()
    private var isHovered = false

    init(entry: TOCEntry, theme: Theme, onClick: @escaping (TOCEntry) -> Void) {
        self.entry = entry
        self.theme = theme
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    private func setupViews() {
        wantsLayer = true

        let indent = CGFloat(entry.level - 1) * 14

        titleField.stringValue = entry.text
        titleField.font = entry.level == 1
            ? .systemFont(ofSize: 12, weight: .semibold)
            : .systemFont(ofSize: 12, weight: .regular)
        titleField.textColor = entry.level == 1 ? theme.textColor : theme.blockquoteColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.usesSingleLineMode = true
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        stripeLayer.isHidden = true
        layer?.addSublayer(stripeLayer)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent + 14),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func layout() {
        super.layout()
        stripeLayer.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        stripeLayer.isHidden = !isHovered && !isActive
        let stripeAlpha: CGFloat = isActive ? 0.8 : 0.5
        stripeLayer.backgroundColor = theme.accentColor.withAlphaComponent(stripeAlpha).cgColor

        let bgAlpha: CGFloat = {
            switch (isActive, isHovered) {
            case (true, true):   return 0.10
            case (true, false):  return 0.04
            case (false, true):  return 0.06
            case (false, false): return 0
            }
        }()
        layer?.backgroundColor = bgAlpha == 0
            ? nil
            : theme.accentColor.withAlphaComponent(bgAlpha).cgColor

        titleField.textColor = isActive
            ? theme.accentColor
            : (entry.level == 1 ? theme.textColor : theme.blockquoteColor)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onClick(entry)
        }
    }
}

private extension NSTextField {
    var kerning: CGFloat {
        get { 0 }
        set {
            let attributed = NSAttributedString(
                string: stringValue,
                attributes: [
                    .font: font as Any,
                    .foregroundColor: textColor as Any,
                    .kern: newValue,
                ]
            )
            attributedStringValue = attributed
        }
    }
}
