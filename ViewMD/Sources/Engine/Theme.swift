import AppKit

protocol Theme: Sendable {
    var name: String { get }

    // Typography
    var baseFontSize: CGFloat { get }
    var fontFamily: String { get }
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

    // Heading sizes (relative to body)
    func headingFont(level: Int) -> NSFont
    func headingColor(level: Int) -> NSColor

    // Computed attribute dictionaries
    var bodyAttributes: [NSAttributedString.Key: Any] { get }
    var inlineCodeAttributes: [NSAttributedString.Key: Any] { get }
    var codeBlockAttributes: [NSAttributedString.Key: Any] { get }
    func headingAttributes(level: Int) -> [NSAttributedString.Key: Any]
}

// MARK: - Default Implementations

extension Theme {

    var bodyFontSize: CGFloat { baseFontSize }
    var codeFontSize: CGFloat { baseFontSize - 1 }

    var bodyFont: NSFont {
        if let font = NSFont(name: fontFamily, size: bodyFontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: bodyFontSize, weight: .regular)
    }

    func headingFont(level: Int) -> NSFont {
        // Scale heading sizes relative to base font size
        let scales: [CGFloat] = [2.15, 1.69, 1.38, 1.15, 1.0, 0.92]
        let size = level >= 1 && level <= 6 ? baseFontSize * scales[level - 1] : baseFontSize
        let weight: NSFont.Weight = level <= 3 ? .bold : .semibold

        if let baseFont = NSFont(name: fontFamily, size: size) {
            // Try to get bold/semibold variant
            let targetTrait: NSFontTraitMask = level <= 3 ? .boldFontMask : .unboldFontMask
            let styledFont = NSFontManager.shared.convert(baseFont, toHaveTrait: targetTrait)
            return styledFont
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 6
        return [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    var inlineCodeAttributes: [NSAttributedString.Key: Any] {
        let codeFont = NSFont(name: fontFamily, size: codeFontSize) ?? NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)

        return [
            .font: codeFont,
            .foregroundColor: codeTextColor,
            .backgroundColor: codeBackgroundColor,
        ]
    }

    var codeBlockAttributes: [NSAttributedString.Key: Any] {
        let codeFont = NSFont(name: fontFamily, size: codeFontSize) ?? NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)

        let block = NSTextBlock()
        block.backgroundColor = codeBackgroundColor
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxY)
        block.setWidth(16, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(16, type: .absoluteValueType, for: .padding, edge: .maxX)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.textBlocks = [block]
        return [
            .font: codeFont,
            .foregroundColor: codeTextColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        let topSpacing: CGFloat = level <= 2 ? 24 : level <= 4 ? 16 : 12
        paragraphStyle.paragraphSpacingBefore = topSpacing
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.lineSpacing = 4
        return [
            .font: headingFont(level: level),
            .foregroundColor: headingColor(level: level),
            .paragraphStyle: paragraphStyle,
        ]
    }
}

// MARK: - Default Theme (System Colors)

struct DefaultTheme: Theme {
    let name = "Default"
    let baseFontSize: CGFloat
    let fontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
    }

    var backgroundColor: NSColor { .textBackgroundColor }
    var textColor: NSColor { .labelColor }
    var linkColor: NSColor { .linkColor }
    var codeBackgroundColor: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.1) }
    var codeTextColor: NSColor { NSColor.systemOrange }
    var blockquoteColor: NSColor { .secondaryLabelColor }
    var blockquoteBarColor: NSColor { .tertiaryLabelColor }

    func headingColor(level: Int) -> NSColor {
        return .labelColor
    }
}
