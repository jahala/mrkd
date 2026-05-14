import AppKit

struct CatppuccinMochaTheme: Theme {
    let name = "Catppuccin Mocha"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    // Catppuccin Mocha palette
    private let base     = NSColor(red: 0x1e/255.0, green: 0x1e/255.0, blue: 0x2e/255.0, alpha: 1.0)
    private let surface0 = NSColor(red: 0x31/255.0, green: 0x32/255.0, blue: 0x44/255.0, alpha: 1.0)
    private let surface1 = NSColor(red: 0x45/255.0, green: 0x47/255.0, blue: 0x5a/255.0, alpha: 1.0)
    private let text     = NSColor(red: 0xcd/255.0, green: 0xd6/255.0, blue: 0xf4/255.0, alpha: 1.0)
    private let subtext0 = NSColor(red: 0xa6/255.0, green: 0xad/255.0, blue: 0xc8/255.0, alpha: 1.0)
    private let mauve    = NSColor(red: 0xcb/255.0, green: 0xa6/255.0, blue: 0xf7/255.0, alpha: 1.0)
    private let sapphire = NSColor(red: 0x74/255.0, green: 0xc7/255.0, blue: 0xec/255.0, alpha: 1.0)
    private let peach    = NSColor(red: 0xfa/255.0, green: 0xb3/255.0, blue: 0x87/255.0, alpha: 1.0)
    private let red      = NSColor(red: 0xf3/255.0, green: 0x8b/255.0, blue: 0xa8/255.0, alpha: 1.0)
    private let green    = NSColor(red: 0xa6/255.0, green: 0xe3/255.0, blue: 0xa1/255.0, alpha: 1.0)

    var backgroundColor: NSColor { base }
    var textColor: NSColor { text }
    var linkColor: NSColor { sapphire }
    var codeBackgroundColor: NSColor { surface0 }
    var codeTextColor: NSColor { text }
    var blockquoteColor: NSColor { subtext0 }
    var blockquoteBarColor: NSColor { surface1 }
    var highlightrTheme: String { "atom-one-dark" }

    func headingColor(level: Int) -> NSColor {
        return mauve
    }

    func admonitionColor(type: AdmonitionType) -> NSColor {
        switch type {
        case .note:      return sapphire
        case .tip:       return green
        case .important: return mauve
        case .warning:   return peach
        case .caution:   return red
        }
    }
}
