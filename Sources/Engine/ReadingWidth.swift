import CoreGraphics

/// How wide the text column may grow. The reader picks one in Settings.
///
/// The limits are chosen by line length in the default body font,
/// SF Mono at 13 pt, which sets about 8 pt per character:
/// - Narrow, 640 pt: about 80 characters, the classic terminal width.
/// - Standard, 800 pt: about 100 characters. This was the only width
///   before the setting existed, so it stays the default.
/// - Wide, 1040 pt: about 130 characters. A 120-column code line fits
///   inside a code block at code sizes up to 13 pt.
/// - Full window: no limit, only the side padding.
enum ReadingWidth: String, CaseIterable {
    case narrow
    case standard
    case wide
    case fullWindow

    static let defaultWidth: ReadingWidth = .standard

    /// The name shown in Settings.
    var title: String {
        switch self {
        case .narrow: return "Narrow"
        case .standard: return "Standard"
        case .wide: return "Wide"
        case .fullWindow: return "Full Window"
        }
    }

    /// The widest the column may be, or nil when it fills the window.
    var maxColumnWidth: CGFloat? {
        switch self {
        case .narrow: return 640
        case .standard: return 800
        case .wide: return 1040
        case .fullWindow: return nil
        }
    }
}

/// Where the text column sits in a view of a given width. The column is
/// centred, never wider than the reading width allows, and always keeps
/// at least `minimumSidePadding` clear on each side.
struct ColumnLayout: Equatable {
    let columnWidth: CGFloat
    let sideInset: CGFloat

    static let minimumSidePadding: CGFloat = 60

    init(viewWidth: CGFloat, readingWidth: ReadingWidth) {
        let available = viewWidth - 2 * Self.minimumSidePadding
        let width = readingWidth.maxColumnWidth.map { min($0, available) } ?? available
        columnWidth = width
        sideInset = max(Self.minimumSidePadding, (viewWidth - width) / 2)
    }

    /// True when the margin beside the column can hold something this wide
    /// without covering the text.
    func marginFits(_ width: CGFloat) -> Bool {
        sideInset >= width
    }
}
