import AppKit

enum AdmonitionType: String, CaseIterable {
    case note, tip, important, warning, caution
}

protocol Theme {
    var name: String { get }

    // Typography
    var baseFontSize: CGFloat { get }
    var fontFamily: String { get }
    var codeFontFamily: String { get }
    var bodyFont: NSFont { get }
    var bodyFontSize: CGFloat { get }
    var codeFontSize: CGFloat { get }

    // Colors
    var backgroundColor: NSColor { get }
    var textColor: NSColor { get }
    var linkColor: NSColor { get }
    var codeBackgroundColor: NSColor { get }
    var codeTextColor: NSColor { get }
    var blockquoteColor: NSColor { get }
    var blockquoteBarColor: NSColor { get }

    // Syntax highlighting
    var highlightrTheme: String { get }

    // Admonitions
    func admonitionColor(type: AdmonitionType) -> NSColor
    func admonitionBackgroundColor(type: AdmonitionType) -> NSColor

    // Heading sizes (relative to body)
    func headingFont(level: Int) -> NSFont
    func headingColor(level: Int) -> NSColor

    // Computed attribute dictionaries
    var bodyAttributes: [NSAttributedString.Key: Any] { get }
    var inlineCodeAttributes: [NSAttributedString.Key: Any] { get }

    /// Each call creates a new NSTextBlock. Consecutive paragraphs sharing
    /// a background (e.g. table rows) must call this ONCE and reuse the result.
    var codeBlockAttributes: [NSAttributedString.Key: Any] { get }

    func headingAttributes(level: Int) -> [NSAttributedString.Key: Any]
}

// MARK: - Default Implementations

extension Theme {

    var bodyFontSize: CGFloat { baseFontSize }
    var codeFontSize: CGFloat { baseFontSize - 1 }
    var codeFontFamily: String { fontFamily }

    var highlightrTheme: String {
        let isDark = (backgroundColor.usingColorSpace(.sRGB)?.brightnessComponent ?? 0.5) < 0.5
        return isDark ? "atom-one-dark" : "atom-one-light"
    }

    func admonitionColor(type: AdmonitionType) -> NSColor {
        switch type {
        case .note:      return .systemBlue
        case .tip:       return .systemGreen
        case .important: return .systemPurple
        case .warning:   return .systemOrange
        case .caution:   return .systemRed
        }
    }

    func admonitionBackgroundColor(type: AdmonitionType) -> NSColor {
        admonitionColor(type: type).withAlphaComponent(0.08)
    }

    /// Create a font from the theme's font family at a specific weight.
    /// Variable fonts (Geist, Inter, SF Pro/Mono) honour intermediate weights;
    /// non-variable fonts fall back to the nearest available weight.
    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: fontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        return NSFont(descriptor: descriptor, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Bump a font's weight up by one notch for emphasis (e.g. strong text).
    /// Below medium → medium, below bold → bold, otherwise → heavy.
    func fontByBumpingWeight(_ font: NSFont) -> NSFont {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let current = (traits?[.weight] as? CGFloat) ?? NSFont.Weight.regular.rawValue

        let target: NSFont.Weight
        if current < NSFont.Weight.medium.rawValue {
            target = .medium
        } else if current < NSFont.Weight.bold.rawValue {
            target = .bold
        } else {
            target = .heavy
        }

        let descriptor = font.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: target],
        ])
        return NSFont(descriptor: descriptor, size: font.pointSize)
            ?? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    var bodyFont: NSFont {
        return font(size: bodyFontSize, weight: .regular)
    }

    func headingFont(level: Int) -> NSFont {
        let scales: [CGFloat] = [2.15, 1.69, 1.38, 1.15, 1.0, 0.92]
        let size = level >= 1 && level <= 6 ? baseFontSize * scales[level - 1] : baseFontSize
        let weight: NSFont.Weight = level <= 3 ? .semibold : .medium
        return font(size: size, weight: weight)
    }

    var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFontSize * 0.35
        paragraphStyle.paragraphSpacing = baseFontSize * 0.5
        return [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .kern: baseFontSize * -0.007,
            .ligature: 1,
        ]
    }

    var inlineCodeAttributes: [NSAttributedString.Key: Any] {
        let codeFont = NSFont(name: codeFontFamily, size: codeFontSize) ?? NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)

        return [
            .font: codeFont,
            .foregroundColor: codeTextColor,
            .inlineCodeBorderColor: codeBackgroundColor,
            .kern: 0 as CGFloat,
            .ligature: 0,
        ]
    }

    var codeBlockAttributes: [NSAttributedString.Key: Any] {
        let codeFont = NSFont(name: codeFontFamily, size: codeFontSize) ?? NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)

        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        block.backgroundColor = codeBackgroundColor
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxY)
        block.setWidth(16, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(16, type: .absoluteValueType, for: .padding, edge: .maxX)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = codeFontSize * 0.2
        paragraphStyle.textBlocks = [block]
        return [
            .font: codeFont,
            .foregroundColor: codeTextColor,
            .paragraphStyle: paragraphStyle,
            .kern: 0 as CGFloat,
            .ligature: 0,
        ]
    }

    func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let headingSize = headingFont(level: level).pointSize
        let paragraphStyle = NSMutableParagraphStyle()
        let topSpacing: CGFloat = level <= 2 ? 24 : level <= 4 ? 16 : 12
        paragraphStyle.paragraphSpacingBefore = topSpacing
        paragraphStyle.paragraphSpacing = 8
        // Proportional line height — larger headings need more leading
        paragraphStyle.lineSpacing = headingSize * 0.25

        // Per-level tracking: tighter for large headings, slightly loose for mid-sizes
        let tracking: [CGFloat] = [-0.3, 0.2, -0.3, -0.15, -0.15, -0.1]
        let kern = level >= 1 && level <= 6 ? tracking[level - 1] : 0

        return [
            .font: headingFont(level: level),
            .foregroundColor: headingColor(level: level),
            .paragraphStyle: paragraphStyle,
            .kern: kern,
            .ligature: 1,
        ]
    }
}

// MARK: - Default Theme (System Colors)

struct DefaultTheme: Theme {
    let name = "Default"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    var backgroundColor: NSColor { .textBackgroundColor }
    var textColor: NSColor { .labelColor }
    var linkColor: NSColor { .linkColor }
    var codeBackgroundColor: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.15) }
    var codeTextColor: NSColor { .labelColor }
    var blockquoteColor: NSColor { .secondaryLabelColor }
    var blockquoteBarColor: NSColor { .tertiaryLabelColor }

    func headingColor(level: Int) -> NSColor {
        return .labelColor
    }
}
