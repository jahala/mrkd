import AppKit

struct CustomTheme: Theme {
    let name: String
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    private let palette: ThemePalette

    init(palette: ThemePalette, baseFontSize: CGFloat, fontFamily: String, codeFontFamily: String) {
        self.name = palette.name
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
        self.palette = palette
    }

    var backgroundColor: NSColor { palette.backgroundColor }
    var textColor: NSColor { palette.textColor }
    var linkColor: NSColor { palette.linkColor }
    var codeBackgroundColor: NSColor { palette.codeBackgroundColor }
    var codeTextColor: NSColor { palette.codeTextColor }
    var blockquoteColor: NSColor { palette.blockquoteColor }
    var blockquoteBarColor: NSColor { palette.blockquoteBarColor }

    func headingColor(level: Int) -> NSColor {
        switch level {
        case 1:    return palette.headingColor
        case 2, 3: return palette.linkColor
        default:   return palette.textColor
        }
    }
}
