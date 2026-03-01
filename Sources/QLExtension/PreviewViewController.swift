import AppKit
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {

    private let maxFileSize = 10_000_000 // 10 MB
    private let phi: CGFloat = 1.618

    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var fileURL: URL?
    private var openButton: NSView!

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

        // Wrap in a plain container so the button floats over the scroll view
        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]
        scrollView.frame = container.bounds
        container.addSubview(scrollView)

        // Floating "Open" button — mirrors main app's OpenWithButton
        openButton = makeOpenButton()
        container.addSubview(openButton)
        openButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            openButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            openButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        view = container
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

            self.fileURL = url

            textView.textStorage?.setAttributedString(attributed)
            scrollView.backgroundColor = theme.backgroundColor

            handler(nil)
        } catch {
            handler(error)
        }
    }

    // MARK: - Theme

    /// Reads a preference from the main app's domain via CFPreferences.
    /// The main app flushes values to disk with CFPreferencesAppSynchronize
    /// so they are visible to this sandboxed extension.
    private static let appID = "com.mrkd.app" as CFString

    private func readPref(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, Self.appID)
    }

    private func resolveTheme() -> Theme {
        let themeName = readPref("selectedTheme") as? String ?? "Default"
        let storedSize = readPref("fontSize") as? Double ?? 0
        let fontSize: CGFloat = storedSize > 0 ? CGFloat(storedSize) : 13.0
        let fontFamily = readPref("fontFamily") as? String ?? "SF Mono"
        let codeFontFamily = readPref("codeFontFamily") as? String ?? "JetBrains Mono"

        let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = makeTheme(named: themeName, isDark: isDark, fontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily)

        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return HighContrastTheme(wrapping: theme)
        }
        return theme
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
        // Use the real home directory (not the sandbox container) to find custom
        // themes installed by the main app. Requires the
        // temporary-exception.files.absolute-path.read-only entitlement.
        let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir!)
        let themesDir = URL(fileURLWithPath: realHome)
            .appendingPathComponent("Library/Application Support/com.mrkd.app/Themes", isDirectory: true)

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

    // MARK: - Open With Button

    private func makeOpenButton() -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 4

        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.title = "Open"
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Open")
        button.imagePosition = .imageTrailing
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(openButtonClicked)

        effect.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: effect.topAnchor),
            button.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            effect.heightAnchor.constraint(equalToConstant: 26),
        ])

        effect.setAccessibilityRole(.button)
        effect.setAccessibilityLabel("Open with another application")

        return effect
    }

    @objc private func openButtonClicked() {
        guard let url = fileURL else { return }

        let menu = NSMenu()

        // The parent app is: QLPlugin.appex → PlugIns → Contents → mrkd.app
        let appexURL = Bundle.main.bundleURL
        let parentAppURL = appexURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // mrkd.app
        let parentAppStd = parentAppURL.standardizedFileURL

        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            .filter { $0.standardizedFileURL != parentAppStd }

        if apps.isEmpty {
            let item = NSMenuItem(title: "No applications available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let iconSize = NSSize(width: 16, height: 16)
            for appURL in apps {
                let appName = appURL.deletingPathExtension().lastPathComponent
                let item = NSMenuItem(title: appName, action: #selector(openWithApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = appURL
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = iconSize
                item.image = icon
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: openButton.bounds.minX, y: openButton.bounds.minY), in: openButton)
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL,
              let url = fileURL else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
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
