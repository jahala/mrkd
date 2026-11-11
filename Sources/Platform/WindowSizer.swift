import AppKit

enum WindowSizer {

    private static let phi: CGFloat = 1.618

    /// The size a new window opens at on a screen with this much room.
    ///
    /// Golden-ratio proportions: the width is the screen's usable width / phi
    /// (about 62 %), and the height is that width / phi. The window is never
    /// narrower than the contents sidebar needs beside the column at this
    /// reading width, as long as the screen has room for that. Otherwise a
    /// laptop would open every document with the sidebar hidden.
    static func defaultSize(visible: NSSize, readingWidth: ReadingWidth) -> NSSize {
        var width = round(visible.width / phi)
        if let sidebarWidth = ColumnLayout.narrowestViewShowingSidebar(readingWidth: readingWidth),
           sidebarWidth <= visible.width {
            width = max(width, sidebarWidth)
        }
        let height = min(round(width / phi), visible.height)
        return NSSize(width: width, height: height)
    }

    /// Minimum window size: 60 characters wide, phi aspect ratio
    static func minimumSize(for theme: Theme) -> NSSize {
        let font = theme.bodyFont
        let mString = NSAttributedString(string: "M", attributes: [.font: font])
        let charWidth = mString.size().width

        let width = max((charWidth * 60) + 64, 480)
        let height = round(width / phi)
        return NSSize(width: width, height: max(height, 300))
    }
}
