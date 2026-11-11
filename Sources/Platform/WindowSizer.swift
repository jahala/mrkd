import AppKit

enum WindowSizer {

    private static let phi: CGFloat = 1.618

    /// How much wider than the sidebar strictly needs a window opens.
    private static let sidebarBreathingRoom: CGFloat = 1.05

    /// The size a new window opens at on a screen with this much room.
    ///
    /// Golden-ratio proportions: the width is the screen's usable width / phi
    /// (about 62 %), and the height is that width / phi. The window is never
    /// narrower than the contents sidebar needs beside the column at this
    /// reading width, plus 5 %, as long as the screen has room for that.
    /// Otherwise a laptop would open every document with the sidebar hidden.
    static func defaultSize(visible: NSSize, readingWidth: ReadingWidth) -> NSSize {
        var width = round(visible.width / phi)
        if let sidebarWidth = ColumnLayout.narrowestViewShowingSidebar(readingWidth: readingWidth),
           sidebarWidth <= visible.width {
            // Exactly wide enough feels cramped, so leave some room. The
            // room gives way to the screen's edge before the sidebar does.
            let roomy = min(round(sidebarWidth * sidebarBreathingRoom), visible.width)
            width = max(width, roomy)
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
