import AppKit

struct HighContrastTheme: Theme {
    private let base: Theme
    let name: String
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(wrapping base: Theme) {
        self.base = base
        self.name = base.name
        self.baseFontSize = base.baseFontSize
        self.fontFamily = base.fontFamily
        self.codeFontFamily = base.codeFontFamily
    }

    var backgroundColor: NSColor { base.backgroundColor }

    var textColor: NSColor {
        // Boost contrast: ensure text is fully opaque and maximum contrast
        let isDark = (base.backgroundColor.usingColorSpace(.sRGB)?.brightnessComponent ?? 0.5) < 0.5
        return isDark ? .white : .black
    }

    var linkColor: NSColor { base.linkColor }
    var codeBackgroundColor: NSColor { base.codeBackgroundColor }
    var codeTextColor: NSColor { base.codeTextColor }

    var blockquoteColor: NSColor {
        // Boost blockquote to be more visible
        let isDark = (base.backgroundColor.usingColorSpace(.sRGB)?.brightnessComponent ?? 0.5) < 0.5
        return isDark ? NSColor(white: 0.8, alpha: 1.0) : NSColor(white: 0.2, alpha: 1.0)
    }

    var blockquoteBarColor: NSColor {
        let isDark = (base.backgroundColor.usingColorSpace(.sRGB)?.brightnessComponent ?? 0.5) < 0.5
        return isDark ? NSColor(white: 0.7, alpha: 1.0) : NSColor(white: 0.3, alpha: 1.0)
    }

    var highlightrTheme: String { base.highlightrTheme }

    func admonitionColor(type: AdmonitionType) -> NSColor { base.admonitionColor(type: type) }
    func admonitionBackgroundColor(type: AdmonitionType) -> NSColor { base.admonitionBackgroundColor(type: type) }

    func headingColor(level: Int) -> NSColor {
        let isDark = (base.backgroundColor.usingColorSpace(.sRGB)?.brightnessComponent ?? 0.5) < 0.5
        return isDark ? .white : .black
    }
}
