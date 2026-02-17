import AppKit

enum WindowSizer {

    private static let phi: CGFloat = 1.618

    /// Calculate ideal window size: phi-proportional to screen
    /// Width  = screen width  / phi  (~61.8% of screen)
    /// Height = width / phi           (phi aspect ratio)
    static func defaultSize(for theme: Theme) -> NSSize {
        guard let screen = NSScreen.main else {
            return NSSize(width: 890, height: 550)
        }

        let visible = screen.visibleFrame
        let width = round(visible.width / phi)
        let height = round(width / phi)

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
