import AppKit
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {

    private let maxFileSize = 10_000_000 // 10 MB
    private let phi: CGFloat = 1.618

    private var scrollView: NSScrollView!
    private var textView: NSTextView!

    override func loadView() {
        let size = phiSize()
        preferredContentSize = size
        let frame = NSRect(origin: .zero, size: size)

        scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize
        textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 82, height: 40)

        scrollView.documentView = textView
        view = scrollView
    }

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int, size > maxFileSize {
                handler(makeError("File too large for preview"))
                return
            }

            FontRegistrar.registerBundledFonts()

            let markdown = try String(contentsOf: url, encoding: .utf8)
            let theme = resolveTheme()
            let attributed = MarkdownRenderer.render(markdown, theme: theme)

            textView.textStorage?.setAttributedString(attributed)
            scrollView.backgroundColor = theme.backgroundColor

            handler(nil)
        } catch {
            handler(error)
        }
    }

    // MARK: - Theme

    private func resolveTheme() -> Theme {
        // Use CFPreferencesCopyAppValue — the official cross-process API.
        // UserDefaults(suiteName:) doesn't work reliably from a sandboxed
        // extension reading the main app's preferences domain.
        let themeName = readPref("selectedTheme") as? String ?? "Default"
        let storedSize = readPref("fontSize") as? Double ?? 0
        let fontSize: CGFloat = storedSize > 0 ? CGFloat(storedSize) : 13.0
        let fontFamily = readPref("fontFamily") as? String ?? "SF Mono"
        let codeFontFamily = readPref("codeFontFamily") as? String ?? "JetBrains Mono"

        let isDark = NSAppearance.current.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = makeTheme(named: themeName, isDark: isDark, fontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily)

        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return HighContrastTheme(wrapping: theme)
        }
        return theme
    }

    private func readPref(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, "com.mrkd.app" as CFString)
    }

    private func makeTheme(named name: String, isDark: Bool, fontSize: CGFloat, fontFamily: String, codeFontFamily: String) -> Theme {
        switch name {
        case "Solarized":
            return isDark ? SolarizedDark(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily) : SolarizedLight(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily)
        case "Monokai":
            return MonokaiTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily)
        case "GitHub":
            return isDark ? GitHubDark(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily) : GitHubLight(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily)
        case "Dracula":
            return DraculaTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily)
        default:
            // Check for a custom imported theme in App Support
            if let palette = loadCustomPalette(named: name) {
                return CustomTheme(palette: palette, baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily)
            }
            return DefaultTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily)
        }
    }

    private func loadCustomPalette(named name: String) -> ThemePalette? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let themesDir = appSupport.appendingPathComponent("com.mrkd.app/Themes", isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil) else {
            return nil
        }

        for file in files {
            let ext = file.pathExtension.lowercased()
            guard ext == "itermcolors" || ext == "json" else { continue }
            if let palette = try? ThemeImporter.parse(from: file), palette.name == name {
                return palette
            }
        }
        return nil
    }

    // MARK: - Sizing

    private func phiSize() -> NSSize {
        guard let screen = NSScreen.main else {
            return NSSize(width: 890, height: 550)
        }
        let visible = screen.visibleFrame
        let width = round(visible.width / phi)
        let height = round(width / phi)
        return NSSize(width: width, height: height)
    }

    // MARK: - Helpers

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "com.mrkd.qlplugin",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
