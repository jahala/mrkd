import AppKit

struct DraculaTheme: Theme {
    let name = "Dracula"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    // Dracula color palette
    private let bg = NSColor(red: 0x28/255.0, green: 0x2a/255.0, blue: 0x36/255.0, alpha: 1.0)
    private let fg = NSColor(red: 0xf8/255.0, green: 0xf8/255.0, blue: 0xf2/255.0, alpha: 1.0)
    private let comment = NSColor(red: 0x62/255.0, green: 0x72/255.0, blue: 0xa4/255.0, alpha: 1.0)
    private let cyan = NSColor(red: 0x8b/255.0, green: 0xe9/255.0, blue: 0xfd/255.0, alpha: 1.0)
    private let green = NSColor(red: 0x50/255.0, green: 0xfa/255.0, blue: 0x7b/255.0, alpha: 1.0)
    private let orange = NSColor(red: 0xff/255.0, green: 0xb8/255.0, blue: 0x6c/255.0, alpha: 1.0)
    private let pink = NSColor(red: 0xff/255.0, green: 0x79/255.0, blue: 0xc6/255.0, alpha: 1.0)
    private let purple = NSColor(red: 0xbd/255.0, green: 0x93/255.0, blue: 0xf9/255.0, alpha: 1.0)
    private let red = NSColor(red: 0xff/255.0, green: 0x55/255.0, blue: 0x55/255.0, alpha: 1.0)
    private let yellow = NSColor(red: 0xf1/255.0, green: 0xfa/255.0, blue: 0x8c/255.0, alpha: 1.0)

    var backgroundColor: NSColor { bg }
    var textColor: NSColor { fg }
    var linkColor: NSColor { cyan }
    var codeBackgroundColor: NSColor {
        NSColor(red: 0x21/255.0, green: 0x22/255.0, blue: 0x2c/255.0, alpha: 1.0)
    }
    var codeTextColor: NSColor { fg }
    var blockquoteColor: NSColor { comment }
    var blockquoteBarColor: NSColor {
        NSColor(red: 0x44/255.0, green: 0x47/255.0, blue: 0x5a/255.0, alpha: 1.0)
    }
    var highlightrTheme: String { "dracula" }

    func headingColor(level: Int) -> NSColor {
        return purple
    }

    func admonitionColor(type: AdmonitionType) -> NSColor {
        switch type {
        case .note:      return cyan
        case .tip:       return green
        case .important: return purple
        case .warning:   return orange
        case .caution:   return red
        }
    }
}
