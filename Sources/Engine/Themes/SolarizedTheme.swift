import AppKit

// MARK: - Solarized Light

struct SolarizedLight: Theme {
    let name = "Solarized Light"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    // Solarized color palette
    private let base03 = NSColor(red: 0x00/255.0, green: 0x2b/255.0, blue: 0x36/255.0, alpha: 1.0)
    private let base02 = NSColor(red: 0x07/255.0, green: 0x36/255.0, blue: 0x42/255.0, alpha: 1.0)
    private let base01 = NSColor(red: 0x58/255.0, green: 0x6e/255.0, blue: 0x75/255.0, alpha: 1.0)
    private let base00 = NSColor(red: 0x65/255.0, green: 0x7b/255.0, blue: 0x83/255.0, alpha: 1.0)
    private let base0 = NSColor(red: 0x83/255.0, green: 0x94/255.0, blue: 0x96/255.0, alpha: 1.0)
    private let base1 = NSColor(red: 0x93/255.0, green: 0xa1/255.0, blue: 0xa1/255.0, alpha: 1.0)
    private let base2 = NSColor(red: 0xee/255.0, green: 0xe8/255.0, blue: 0xd5/255.0, alpha: 1.0)
    private let base3 = NSColor(red: 0xfd/255.0, green: 0xf6/255.0, blue: 0xe3/255.0, alpha: 1.0)

    private let yellow = NSColor(red: 0xb5/255.0, green: 0x89/255.0, blue: 0x00/255.0, alpha: 1.0)
    private let orange = NSColor(red: 0xcb/255.0, green: 0x4b/255.0, blue: 0x16/255.0, alpha: 1.0)
    private let red = NSColor(red: 0xdc/255.0, green: 0x32/255.0, blue: 0x2f/255.0, alpha: 1.0)
    private let magenta = NSColor(red: 0xd3/255.0, green: 0x36/255.0, blue: 0x82/255.0, alpha: 1.0)
    private let violet = NSColor(red: 0x6c/255.0, green: 0x71/255.0, blue: 0xc4/255.0, alpha: 1.0)
    private let blue = NSColor(red: 0x26/255.0, green: 0x8b/255.0, blue: 0xd2/255.0, alpha: 1.0)
    private let cyan = NSColor(red: 0x2a/255.0, green: 0xa1/255.0, blue: 0x98/255.0, alpha: 1.0)
    private let green = NSColor(red: 0x85/255.0, green: 0x99/255.0, blue: 0x00/255.0, alpha: 1.0)

    var backgroundColor: NSColor { base3 }
    var textColor: NSColor { base00 }
    var linkColor: NSColor { blue }
    var codeBackgroundColor: NSColor { base2 }
    var codeTextColor: NSColor { base00 }
    var blockquoteColor: NSColor { base01 }
    var blockquoteBarColor: NSColor { base1 }
    var highlightrTheme: String { "solarized-light" }

    func headingColor(level: Int) -> NSColor {
        return base01
    }

    func admonitionColor(type: AdmonitionType) -> NSColor {
        switch type {
        case .note:      return blue
        case .tip:       return cyan
        case .important: return violet
        case .warning:   return yellow
        case .caution:   return red
        }
    }
}

// MARK: - Solarized Dark

struct SolarizedDark: Theme {
    let name = "Solarized Dark"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    // Solarized color palette
    private let base03 = NSColor(red: 0x00/255.0, green: 0x2b/255.0, blue: 0x36/255.0, alpha: 1.0)
    private let base02 = NSColor(red: 0x07/255.0, green: 0x36/255.0, blue: 0x42/255.0, alpha: 1.0)
    private let base01 = NSColor(red: 0x58/255.0, green: 0x6e/255.0, blue: 0x75/255.0, alpha: 1.0)
    private let base00 = NSColor(red: 0x65/255.0, green: 0x7b/255.0, blue: 0x83/255.0, alpha: 1.0)
    private let base0 = NSColor(red: 0x83/255.0, green: 0x94/255.0, blue: 0x96/255.0, alpha: 1.0)
    private let base1 = NSColor(red: 0x93/255.0, green: 0xa1/255.0, blue: 0xa1/255.0, alpha: 1.0)
    private let base2 = NSColor(red: 0xee/255.0, green: 0xe8/255.0, blue: 0xd5/255.0, alpha: 1.0)
    private let base3 = NSColor(red: 0xfd/255.0, green: 0xf6/255.0, blue: 0xe3/255.0, alpha: 1.0)

    private let yellow = NSColor(red: 0xb5/255.0, green: 0x89/255.0, blue: 0x00/255.0, alpha: 1.0)
    private let orange = NSColor(red: 0xcb/255.0, green: 0x4b/255.0, blue: 0x16/255.0, alpha: 1.0)
    private let red = NSColor(red: 0xdc/255.0, green: 0x32/255.0, blue: 0x2f/255.0, alpha: 1.0)
    private let magenta = NSColor(red: 0xd3/255.0, green: 0x36/255.0, blue: 0x82/255.0, alpha: 1.0)
    private let violet = NSColor(red: 0x6c/255.0, green: 0x71/255.0, blue: 0xc4/255.0, alpha: 1.0)
    private let blue = NSColor(red: 0x26/255.0, green: 0x8b/255.0, blue: 0xd2/255.0, alpha: 1.0)
    private let cyan = NSColor(red: 0x2a/255.0, green: 0xa1/255.0, blue: 0x98/255.0, alpha: 1.0)
    private let green = NSColor(red: 0x85/255.0, green: 0x99/255.0, blue: 0x00/255.0, alpha: 1.0)

    var backgroundColor: NSColor { base03 }
    var textColor: NSColor { base0 }
    var linkColor: NSColor { blue }
    var codeBackgroundColor: NSColor { base02 }
    var codeTextColor: NSColor { base0 }
    var blockquoteColor: NSColor { base1 }
    var blockquoteBarColor: NSColor { base01 }
    var highlightrTheme: String { "solarized-dark" }

    func headingColor(level: Int) -> NSColor {
        return base1
    }

    func admonitionColor(type: AdmonitionType) -> NSColor {
        switch type {
        case .note:      return blue
        case .tip:       return cyan
        case .important: return violet
        case .warning:   return yellow
        case .caution:   return red
        }
    }
}
