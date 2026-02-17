import AppKit

// MARK: - GitHub Light

struct GitHubLight: Theme {
    let name = "GitHub Light"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    private let bg = NSColor(red: 0xff/255.0, green: 0xff/255.0, blue: 0xff/255.0, alpha: 1.0)
    private let fg = NSColor(red: 0x1f/255.0, green: 0x23/255.0, blue: 0x28/255.0, alpha: 1.0)
    private let link = NSColor(red: 0x09/255.0, green: 0x69/255.0, blue: 0xda/255.0, alpha: 1.0)
    private let codeBg = NSColor(red: 0xf6/255.0, green: 0xf8/255.0, blue: 0xfa/255.0, alpha: 1.0)
    private let codeText = NSColor(red: 0x1f/255.0, green: 0x23/255.0, blue: 0x28/255.0, alpha: 1.0)
    private let quote = NSColor(red: 0x59/255.0, green: 0x63/255.0, blue: 0x6e/255.0, alpha: 1.0)
    private let quoteBar = NSColor(red: 0xd0/255.0, green: 0xd7/255.0, blue: 0xde/255.0, alpha: 1.0)

    var backgroundColor: NSColor { bg }
    var textColor: NSColor { fg }
    var linkColor: NSColor { link }
    var codeBackgroundColor: NSColor { codeBg }
    var codeTextColor: NSColor { codeText }
    var blockquoteColor: NSColor { quote }
    var blockquoteBarColor: NSColor { quoteBar }
    var highlightrTheme: String { "github" }

    func headingColor(level: Int) -> NSColor {
        return fg
    }
}

// MARK: - GitHub Dark

struct GitHubDark: Theme {
    let name = "GitHub Dark"
    let baseFontSize: CGFloat
    let fontFamily: String
    let codeFontFamily: String

    init(baseFontSize: CGFloat = 13, fontFamily: String = "SF Mono", codeFontFamily: String = "SF Mono") {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
    }

    private let bg = NSColor(red: 0x0d/255.0, green: 0x11/255.0, blue: 0x17/255.0, alpha: 1.0)
    private let fg = NSColor(red: 0xe6/255.0, green: 0xed/255.0, blue: 0xf3/255.0, alpha: 1.0)
    private let link = NSColor(red: 0x58/255.0, green: 0xa6/255.0, blue: 0xff/255.0, alpha: 1.0)
    private let codeBg = NSColor(red: 0x16/255.0, green: 0x1b/255.0, blue: 0x22/255.0, alpha: 1.0)
    private let codeText = NSColor(red: 0xe6/255.0, green: 0xed/255.0, blue: 0xf3/255.0, alpha: 1.0)
    private let quote = NSColor(red: 0x8b/255.0, green: 0x94/255.0, blue: 0x9e/255.0, alpha: 1.0)
    private let quoteBar = NSColor(red: 0x30/255.0, green: 0x36/255.0, blue: 0x3d/255.0, alpha: 1.0)

    var backgroundColor: NSColor { bg }
    var textColor: NSColor { fg }
    var linkColor: NSColor { link }
    var codeBackgroundColor: NSColor { codeBg }
    var codeTextColor: NSColor { codeText }
    var blockquoteColor: NSColor { quote }
    var blockquoteBarColor: NSColor { quoteBar }
    var highlightrTheme: String { "github-dark" }

    func headingColor(level: Int) -> NSColor {
        return fg
    }
}
