import AppKit

enum WindowSizer {

    /// Calculate ideal window size based on theme font metrics
    static func defaultSize(for theme: Theme) -> NSSize {
        let font = theme.bodyFont

        // Measure character width using NSAttributedString
        let mString = NSAttributedString(string: "M", attributes: [.font: font])
        let charWidth = mString.size().width

        // Target: 110 characters visible width (middle of 100-120 range)
        let targetChars: CGFloat = 110
        let contentPadding: CGFloat = 64 // 32pt each side (textContainerInset)
        let windowChrome: CGFloat = 0 // no additional chrome

        let width = (charWidth * targetChars) + contentPadding + windowChrome

        // Height: golden ratio proportion, capped at 85% screen
        let goldenRatio: CGFloat = 1.618
        var height = width / goldenRatio

        // Cap to screen bounds
        if let screen = NSScreen.main {
            let maxWidth = screen.visibleFrame.width * 0.9
            let maxHeight = screen.visibleFrame.height * 0.85
            let cappedWidth = min(width, maxWidth)
            height = min(height, maxHeight)
            return NSSize(width: cappedWidth, height: height)
        }

        return NSSize(width: width, height: height)
    }

    /// Minimum window size: 60 characters wide
    static func minimumSize(for theme: Theme) -> NSSize {
        let font = theme.bodyFont

        // Measure character width using NSAttributedString
        let mString = NSAttributedString(string: "M", attributes: [.font: font])
        let charWidth = mString.size().width

        let width = (charWidth * 60) + 64
        return NSSize(width: max(width, 480), height: 400)
    }
}
