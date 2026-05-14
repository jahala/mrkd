import AppKit

struct SnazzyTheme: Theme {
    let name = "Snazzy"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    // Snazzy iTerm2 palette — sindresorhus/iterm2-snazzy/Snazzy.itermcolors
    private let bg          = NSColor(red: 0x27/255.0, green: 0x29/255.0, blue: 0x35/255.0, alpha: 1.0)
    private let fg          = NSColor(red: 0xef/255.0, green: 0xf0/255.0, blue: 0xea/255.0, alpha: 1.0)
    private let red         = NSColor(red: 0xff/255.0, green: 0x5b/255.0, blue: 0x56/255.0, alpha: 1.0)
    private let green       = NSColor(red: 0x5a/255.0, green: 0xf7/255.0, blue: 0x8d/255.0, alpha: 1.0)
    private let yellow      = NSColor(red: 0xf3/255.0, green: 0xf9/255.0, blue: 0x9c/255.0, alpha: 1.0)
    private let blue        = NSColor(red: 0x57/255.0, green: 0xc7/255.0, blue: 0xfe/255.0, alpha: 1.0)
    private let magenta     = NSColor(red: 0xff/255.0, green: 0x69/255.0, blue: 0xc0/255.0, alpha: 1.0)
    private let cyan        = NSColor(red: 0x9a/255.0, green: 0xec/255.0, blue: 0xfe/255.0, alpha: 1.0)
    private let brightBlack = NSColor(red: 0x68/255.0, green: 0x67/255.0, blue: 0x67/255.0, alpha: 1.0)
    private let link        = NSColor(red: 0x4a/255.0, green: 0xaa/255.0, blue: 0xda/255.0, alpha: 1.0)
    // Code background: slightly darker than bg. Snazzy doesn't define this slot — derived to read as inset.
    private let codeBg      = NSColor(red: 0x1e/255.0, green: 0x20/255.0, blue: 0x29/255.0, alpha: 1.0)
    // Blockquote bar: midway between bg and brightBlack — quiet but visible.
    private let quoteBar    = NSColor(red: 0x3d/255.0, green: 0x3f/255.0, blue: 0x4a/255.0, alpha: 1.0)

    var backgroundColor: NSColor { bg }
    var textColor: NSColor { fg }
    var linkColor: NSColor { blue }
    var codeBackgroundColor: NSColor { codeBg }
    var codeTextColor: NSColor { fg }
    var blockquoteColor: NSColor { brightBlack }
    var blockquoteBarColor: NSColor { quoteBar }
    var highlightrTheme: String { "atom-one-dark" }

    func headingColor(level: Int) -> NSColor {
        return magenta
    }

    func admonitionColor(type: AdmonitionType) -> NSColor {
        switch type {
        case .note:      return blue
        case .tip:       return green
        case .important: return magenta
        case .warning:   return yellow
        case .caution:   return red
        }
    }
}
