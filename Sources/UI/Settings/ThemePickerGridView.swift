import AppKit

@MainActor
final class ThemePickerGridView: NSView {

    // MARK: - Properties

    private let themeNames: [String]
    private var themeCards: [ThemeCardView] = []
    private var selectedThemeName: String
    private var focusedIndex: Int = 0

    private let columns = 3
    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 140
    private let spacing: CGFloat = 12

    var onImportTheme: (() -> Void)?
    private var importCard: NSControl?

    // MARK: - Initialization

    init(selectedTheme: String) {
        self.themeNames = ThemeManager.shared.availableThemeNames()
        self.selectedThemeName = selectedTheme

        super.init(frame: .zero)

        setupCards()
        setupLayout()

        // Find and focus the selected theme
        if let index = themeNames.firstIndex(of: selectedTheme) {
            focusedIndex = index
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupCards() {
        for (index, themeName) in themeNames.enumerated() {
            let card = ThemeCardView(themeName: themeName)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.target = self
            card.action = #selector(cardClicked(_:))
            card.tag = index
            themeCards.append(card)
            addSubview(card)
        }

        updateSelection()

        // Add "Import Theme..." card
        let card = ImportThemeCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.target = self
        card.action = #selector(importClicked(_:))
        importCard = card
        addSubview(card)
    }

    private func setupLayout() {
        // Calculate required rows
        let totalItems = themeNames.count + 1  // +1 for import card
        let rows = (totalItems + columns - 1) / columns
        let totalWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing
        let totalHeight = CGFloat(rows) * cardHeight + CGFloat(rows - 1) * spacing

        // Position cards in a grid
        for (index, card) in themeCards.enumerated() {
            let row = index / columns
            let col = index % columns

            let x = CGFloat(col) * (cardWidth + spacing)
            let y = CGFloat(row) * (cardHeight + spacing)

            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: x),
                card.topAnchor.constraint(equalTo: topAnchor, constant: y),
                card.widthAnchor.constraint(equalToConstant: cardWidth),
                card.heightAnchor.constraint(equalToConstant: cardHeight)
            ])
        }

        // Position import card as last item
        if let importCard = importCard {
            let importIndex = themeNames.count
            let row = importIndex / columns
            let col = importIndex % columns
            let x = CGFloat(col) * (cardWidth + spacing)
            let y = CGFloat(row) * (cardHeight + spacing)

            NSLayoutConstraint.activate([
                importCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: x),
                importCard.topAnchor.constraint(equalTo: topAnchor, constant: y),
                importCard.widthAnchor.constraint(equalToConstant: cardWidth),
                importCard.heightAnchor.constraint(equalToConstant: cardHeight)
            ])
        }

        // Set our own size
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: totalWidth),
            heightAnchor.constraint(equalToConstant: totalHeight)
        ])
    }

    // MARK: - Actions

    @objc private func importClicked(_ sender: Any) {
        onImportTheme?()
    }

    @objc private func cardClicked(_ sender: ThemeCardView) {
        guard sender.tag >= 0 && sender.tag < themeNames.count else { return }
        selectTheme(at: sender.tag)
    }

    private func selectTheme(at index: Int) {
        selectedThemeName = themeNames[index]
        ThemeManager.shared.selectedThemeName = selectedThemeName
        updateSelection()
    }

    private func updateSelection() {
        for (index, card) in themeCards.enumerated() {
            card.isSelected = themeNames[index] == selectedThemeName
            card.isFocused = index == focusedIndex
        }
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            updateSelection()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            updateSelection()
        }
        return result
    }

    // MARK: - Keyboard Navigation

    override func keyDown(with event: NSEvent) {
        // Use interpretKeyEvents for proper arrow key handling
        interpretKeyEvents([event])
    }

    override func moveLeft(_ sender: Any?) {
        if focusedIndex > 0 {
            focusedIndex -= 1
            updateSelection()
        }
    }

    override func moveRight(_ sender: Any?) {
        if focusedIndex < themeNames.count - 1 {
            focusedIndex += 1
            updateSelection()
        }
    }

    override func moveUp(_ sender: Any?) {
        if focusedIndex >= columns {
            focusedIndex -= columns
            updateSelection()
        }
    }

    override func moveDown(_ sender: Any?) {
        let newIndex = focusedIndex + columns
        if newIndex < themeNames.count {
            focusedIndex = newIndex
            updateSelection()
        }
    }

    override func insertNewline(_ sender: Any?) {
        selectTheme(at: focusedIndex)
    }

    override func insertText(_ insertString: Any) {
        if let str = insertString as? String, str == " " {
            selectTheme(at: focusedIndex)
        }
    }
}

// MARK: - Theme Card View

@MainActor
private final class ThemeCardView: NSControl {

    private let themeName: String
    private let nameLabel: NSTextField
    private let previewTextView: NSTextView
    private let scrollView: NSScrollView

    var isSelected: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    var isFocused: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    // Sample markdown for preview
    private static let sampleMarkdown = """
    # Heading

    Text with **bold** and `code`.

    ```swift
    let x = 42
    ```
    """

    init(themeName: String) {
        self.themeName = themeName

        // Name label
        self.nameLabel = NSTextField(labelWithString: themeName)
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Preview text view
        self.previewTextView = NSTextView()
        previewTextView.isEditable = false
        previewTextView.isSelectable = false
        previewTextView.drawsBackground = true
        previewTextView.textContainerInset = NSSize(width: 4, height: 4)

        // Scroll view for preview
        self.scrollView = NSScrollView()
        scrollView.documentView = previewTextView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        addSubview(nameLabel)
        addSubview(scrollView)

        wantsLayer = true
        layer?.cornerRadius = 8

        setupLayout()
        renderPreview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    private func renderPreview() {
        // Get both light and dark variants of this theme
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let theme = ThemeManager.shared.theme(named: themeName, isDark: isDark) else { return }

        // Render the sample markdown at a small size for preview
        let attributedString = MarkdownRenderer.render(Self.sampleMarkdown, theme: theme)

        // Scale down the font sizes for preview (make it ~60% of normal size)
        let scaledString = NSMutableAttributedString(attributedString: attributedString)
        scaledString.enumerateAttribute(.font, in: NSRange(location: 0, length: scaledString.length)) { value, range, _ in
            if let font = value as? NSFont {
                let smallerFont = NSFont(name: font.fontName, size: font.pointSize * 0.6) ?? font
                scaledString.addAttribute(.font, value: smallerFont, range: range)
            }
        }

        previewTextView.textStorage?.setAttributedString(scaledString)
        previewTextView.backgroundColor = theme.backgroundColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw border
        let borderWidth: CGFloat = isSelected ? 2 : 1
        let borderColor = isSelected ? NSColor.controlAccentColor : NSColor.separatorColor

        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
                                      xRadius: 8,
                                      yRadius: 8)
        borderPath.lineWidth = borderWidth
        borderColor.setStroke()
        borderPath.stroke()

        // Draw focus ring if focused
        if isFocused, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            NSFocusRingPlacement.only.set()

            let focusPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                         xRadius: 8,
                                         yRadius: 8)
            focusPath.fill()

            context.restoreGState()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return self for all clicks within the card, so the preview
        // scroll view / text view don't absorb mouse events.
        return super.hitTest(point) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if let action = action, let target = target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override var acceptsFirstResponder: Bool { false }
}

// MARK: - Import Theme Card View

@MainActor
private final class ImportThemeCardView: NSControl {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Dashed border
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
        borderPath.lineWidth = 1.5
        let dashPattern: [CGFloat] = [6, 4]
        borderPath.setLineDash(dashPattern, count: 2, phase: 0)
        NSColor.tertiaryLabelColor.setStroke()
        borderPath.stroke()

        // "+" symbol
        let plusFont = NSFont.systemFont(ofSize: 32, weight: .light)
        let plusAttrs: [NSAttributedString.Key: Any] = [
            .font: plusFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let plusStr = NSAttributedString(string: "+", attributes: plusAttrs)
        let plusSize = plusStr.size()
        let plusOrigin = NSPoint(
            x: bounds.midX - plusSize.width / 2,
            y: bounds.midY - plusSize.height / 2 + 8
        )
        plusStr.draw(at: plusOrigin)

        // "Import Theme..." label
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let labelStr = NSAttributedString(string: "Import Theme\u{2026}", attributes: labelAttrs)
        let labelSize = labelStr.size()
        let labelOrigin = NSPoint(
            x: bounds.midX - labelSize.width / 2,
            y: bounds.midY - plusSize.height / 2 - 8
        )
        labelStr.draw(at: labelOrigin)
    }

    override func mouseDown(with event: NSEvent) {
        if let action = action, let target = target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override var acceptsFirstResponder: Bool { false }
}
