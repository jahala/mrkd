import AppKit

@MainActor
final class FontSizeManager {

    static let shared = FontSizeManager()

    private let minFontSize: CGFloat = 9
    private let maxFontSize: CGFloat = 36
    private let defaultFontSize: CGFloat = 13

    private init() {}

    // MARK: - Font Size Actions

    @objc func increaseFontSize() {
        let currentSize = ThemeManager.shared.fontSize
        let newSize = min(currentSize + 1, maxFontSize)
        if newSize != currentSize {
            ThemeManager.shared.fontSize = newSize
        }
    }

    @objc func decreaseFontSize() {
        let currentSize = ThemeManager.shared.fontSize
        let newSize = max(currentSize - 1, minFontSize)
        if newSize != currentSize {
            ThemeManager.shared.fontSize = newSize
        }
    }

    @objc func resetFontSize() {
        ThemeManager.shared.fontSize = defaultFontSize
    }
}
