import AppKit

struct HighContrastTheme: Theme {
    private let base: Theme
    let name: String
    let baseFontSize: CGFloat
    let fontFamily: String

    init(wrapping base: Theme) {
        self.base = base
        self.name = base.name
        self.baseFontSize = base.baseFontSize
        self.fontFamily = base.fontFamily
    }

    var backgroundColor: NSColor { base.backgroundColor }

    var textColor: NSColor {
        // Boost contrast: ensure text is fully opaque and maximum contrast
        let bg = base.backgroundColor
        let isDark = bg.brightnessComponent < 0.5
        return isDark ? .white : .black
    }

    var linkColor: NSColor { base.linkColor }
    var codeBackgroundColor: NSColor { base.codeBackgroundColor }
    var codeTextColor: NSColor { base.codeTextColor }

    var blockquoteColor: NSColor {
        // Boost blockquote to be more visible
        let bg = base.backgroundColor
        let isDark = bg.brightnessComponent < 0.5
        return isDark ? NSColor(white: 0.8, alpha: 1.0) : NSColor(white: 0.2, alpha: 1.0)
    }

    var blockquoteBarColor: NSColor {
        let bg = base.backgroundColor
        let isDark = bg.brightnessComponent < 0.5
        return isDark ? NSColor(white: 0.7, alpha: 1.0) : NSColor(white: 0.3, alpha: 1.0)
    }

    func headingColor(level: Int) -> NSColor {
        let bg = base.backgroundColor
        let isDark = bg.brightnessComponent < 0.5
        return isDark ? .white : .black
    }
}
