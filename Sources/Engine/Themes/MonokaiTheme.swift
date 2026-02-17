import AppKit

struct MonokaiTheme: Theme {
    let name = "Monokai"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    // Monokai color palette
    private let bg = NSColor(red: 0x27/255.0, green: 0x28/255.0, blue: 0x22/255.0, alpha: 1.0)
    private let fg = NSColor(red: 0xf8/255.0, green: 0xf8/255.0, blue: 0xf2/255.0, alpha: 1.0)
    private let comment = NSColor(red: 0x75/255.0, green: 0x71/255.0, blue: 0x5e/255.0, alpha: 1.0)
    private let red = NSColor(red: 0xf9/255.0, green: 0x26/255.0, blue: 0x72/255.0, alpha: 1.0)
    private let orange = NSColor(red: 0xfd/255.0, green: 0x97/255.0, blue: 0x1f/255.0, alpha: 1.0)
    private let yellow = NSColor(red: 0xe6/255.0, green: 0xdb/255.0, blue: 0x74/255.0, alpha: 1.0)
    private let green = NSColor(red: 0xa6/255.0, green: 0xe2/255.0, blue: 0x2e/255.0, alpha: 1.0)
    private let blue = NSColor(red: 0x66/255.0, green: 0xd9/255.0, blue: 0xef/255.0, alpha: 1.0)
    private let purple = NSColor(red: 0xae/255.0, green: 0x81/255.0, blue: 0xff/255.0, alpha: 1.0)

    var backgroundColor: NSColor { bg }
    var textColor: NSColor { fg }
    var linkColor: NSColor { blue }
    var codeBackgroundColor: NSColor {
        NSColor(red: 0x1e/255.0, green: 0x1f/255.0, blue: 0x1c/255.0, alpha: 1.0)
    }
    var codeTextColor: NSColor { fg }
    var blockquoteColor: NSColor { comment }
    var blockquoteBarColor: NSColor {
        NSColor(red: 0x49/255.0, green: 0x48/255.0, blue: 0x3e/255.0, alpha: 1.0)
    }
    var highlightrTheme: String { "monokai" }

    func headingColor(level: Int) -> NSColor {
        return green
    }

    func admonitionColor(type: AdmonitionType) -> NSColor {
        switch type {
        case .note:      return blue
        case .tip:       return green
        case .important: return purple
        case .warning:   return orange
        case .caution:   return red
        }
    }
}
