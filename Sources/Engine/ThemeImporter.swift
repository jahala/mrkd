import AppKit

// MARK: - ThemePalette

struct ThemePalette {
    let name: String
    let isDark: Bool
    let backgroundColor: NSColor
    let textColor: NSColor
    let linkColor: NSColor
    let codeTextColor: NSColor
    let codeBackgroundColor: NSColor
    let blockquoteColor: NSColor
    let blockquoteBarColor: NSColor
    let headingColor: NSColor
    let accentColor: NSColor
}

// MARK: - ThemeImportError

enum ThemeImportError: Error, LocalizedError {
    case unsupportedFormat(String)
    case invalidData(String)
    case missingRequiredColor(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported theme format: '\(ext)'. Expected .itermcolors or .json."
        case .invalidData(let detail):
            return "Invalid theme data: \(detail)"
        case .missingRequiredColor(let key):
            return "Missing required color key: '\(key)'"
        }
    }
}

// MARK: - ThemeImporter

enum ThemeImporter {

    // MARK: - Public Entry Point

    static func parse(from url: URL) throws -> ThemePalette {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent
        let data = try Data(contentsOf: url)

        switch ext {
        case "itermcolors":
            return try parseITerm2(from: data, name: name)
        case "json":
            return try parseVSCode(from: data, name: name)
        default:
            throw ThemeImportError.unsupportedFormat(ext.isEmpty ? "(no extension)" : ext)
        }
    }

    // MARK: - iTerm2 Parser

    static func parseITerm2(from data: Data, name: String) throws -> ThemePalette {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)

        guard let plist = raw as? [String: Any] else {
            throw ThemeImportError.invalidData("Root object is not a dictionary")
        }

        guard let bg = iTermColor(from: plist, key: "Background Color") else {
            throw ThemeImportError.missingRequiredColor("Background Color")
        }
        guard let fg = iTermColor(from: plist, key: "Foreground Color") else {
            throw ThemeImportError.missingRequiredColor("Foreground Color")
        }

        let brightness = colorBrightness(bg)
        let isDark = brightness < 0.5
        let codeBg = derivedCodeBackground(from: bg, isDark: isDark)

        let linkColor = iTermColor(from: plist, key: "Ansi 4 Color") ?? .systemBlue
        let codeTextColor = iTermColor(from: plist, key: "Ansi 2 Color") ?? fg
        let blockquoteColor = iTermColor(from: plist, key: "Ansi 8 Color") ?? fg.withAlphaComponent(0.6)
        let headingColor = iTermColor(from: plist, key: "Ansi 5 Color") ?? fg
        let accentColor = iTermColor(from: plist, key: "Ansi 6 Color") ?? fg

        return ThemePalette(
            name: name,
            isDark: isDark,
            backgroundColor: bg,
            textColor: fg,
            linkColor: linkColor,
            codeTextColor: codeTextColor,
            codeBackgroundColor: codeBg,
            blockquoteColor: blockquoteColor,
            blockquoteBarColor: blockquoteColor,
            headingColor: headingColor,
            accentColor: accentColor
        )
    }

    // MARK: - VS Code Parser

    static func parseVSCode(from data: Data, name: String) throws -> ThemePalette {
        let raw = try JSONSerialization.jsonObject(with: data, options: [])

        guard let json = raw as? [String: Any] else {
            throw ThemeImportError.invalidData("Root object is not a dictionary")
        }

        let colors = json["colors"] as? [String: String] ?? [:]
        let tokenColors = json["tokenColors"] as? [[String: Any]] ?? []

        guard let bgHex = colors["editor.background"],
              let bg = hexColor(bgHex) else {
            throw ThemeImportError.missingRequiredColor("editor.background")
        }
        guard let fgHex = colors["editor.foreground"],
              let fg = hexColor(fgHex) else {
            throw ThemeImportError.missingRequiredColor("editor.foreground")
        }

        let isDark: Bool
        if let typeField = json["type"] as? String {
            isDark = typeField.lowercased() == "dark"
        } else {
            isDark = colorBrightness(bg) < 0.5
        }

        let resolvedName: String
        if let jsonName = json["name"] as? String, !jsonName.isEmpty {
            resolvedName = jsonName
        } else {
            resolvedName = name
        }

        let codeBg = derivedCodeBackground(from: bg, isDark: isDark)

        let linkColor = findTokenColor(in: tokenColors, matching: ["markup.underline.link", "string.other.link"])
            ?? hexColor(colors["terminal.ansiBrightBlue"] ?? "") ?? .systemBlue

        let codeTextColor = findTokenColor(in: tokenColors, matching: ["markup.inline.raw", "markup.raw"])
            ?? hexColor(colors["terminal.ansiGreen"] ?? "") ?? fg

        let blockquoteColor = findTokenColor(in: tokenColors, matching: ["markup.quote", "markup.quote.markdown"])
            ?? hexColor(colors["terminal.ansiBrightBlack"] ?? "") ?? fg.withAlphaComponent(0.6)

        let headingColor = findTokenColor(in: tokenColors, matching: ["markup.heading", "entity.name.section"])
            ?? hexColor(colors["terminal.ansiMagenta"] ?? "") ?? fg

        let accentColor = findTokenColor(in: tokenColors, matching: ["keyword", "keyword.control"])
            ?? hexColor(colors["terminal.ansiCyan"] ?? "") ?? fg

        return ThemePalette(
            name: resolvedName,
            isDark: isDark,
            backgroundColor: bg,
            textColor: fg,
            linkColor: linkColor,
            codeTextColor: codeTextColor,
            codeBackgroundColor: codeBg,
            blockquoteColor: blockquoteColor,
            blockquoteBarColor: blockquoteColor,
            headingColor: headingColor,
            accentColor: accentColor
        )
    }

    // MARK: - iTerm2 Helpers

    private static func iTermColor(from plist: [String: Any], key: String) -> NSColor? {
        guard let entry = plist[key] as? [String: Any] else { return nil }

        // Components are stored as either Double or NSNumber
        func component(_ k: String) -> Double? {
            if let d = entry[k] as? Double { return d }
            if let n = entry[k] as? NSNumber { return n.doubleValue }
            return nil
        }

        guard let r = component("Red Component"),
              let g = component("Green Component"),
              let b = component("Blue Component") else {
            return nil
        }
        let a = component("Alpha Component") ?? 1.0

        return NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    // MARK: - VS Code Helpers

    private static func hexColor(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s = String(s.dropFirst())

        // Accept RRGGBB or RRGGBBAA
        guard s.count == 6 || s.count == 8 else { return nil }
        guard let value = UInt64(s, radix: 16) else { return nil }

        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255.0
            g = CGFloat((value >> 16) & 0xFF) / 255.0
            b = CGFloat((value >> 8)  & 0xFF) / 255.0
            a = CGFloat( value        & 0xFF) / 255.0
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255.0
            g = CGFloat((value >> 8)  & 0xFF) / 255.0
            b = CGFloat( value        & 0xFF) / 255.0
            a = 1.0
        }

        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func findTokenColor(in tokenColors: [[String: Any]], matching scopes: [String]) -> NSColor? {
        for entry in tokenColors {
            guard let settings = entry["settings"] as? [String: Any],
                  let fgHex = settings["foreground"] as? String else { continue }

            // scope can be a String or [String]
            let entryScopes: [String]
            if let single = entry["scope"] as? String {
                entryScopes = [single]
            } else if let multi = entry["scope"] as? [String] {
                entryScopes = multi
            } else {
                continue
            }

            // Match if any entry scope has a prefix-overlap with any target scope
            let matched = entryScopes.contains { entryScope in
                scopes.contains { target in
                    entryScope == target
                        || entryScope.hasPrefix(target + ".")
                        || target.hasPrefix(entryScope + ".")
                }
            }

            if matched, let color = hexColor(fgHex) {
                return color
            }
        }
        return nil
    }

    // MARK: - Shared Color Utilities

    /// Perceived brightness using sRGB luminance coefficients (ITU-R BT.709).
    private static func colorBrightness(_ color: NSColor) -> CGFloat {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            return color.brightnessComponent
        }
        return 0.2126 * srgb.redComponent
             + 0.7152 * srgb.greenComponent
             + 0.0722 * srgb.blueComponent
    }

    /// Derive a code-block background by nudging the editor background slightly
    /// toward contrast: darker for dark themes, lighter for light themes.
    private static func derivedCodeBackground(from base: NSColor, isDark: Bool) -> NSColor {
        guard let srgb = base.usingColorSpace(.sRGB) else { return base }

        let factor: CGFloat = isDark ? 1.15 : 0.92
        let r = min(srgb.redComponent   * factor, 1.0)
        let g = min(srgb.greenComponent * factor, 1.0)
        let b = min(srgb.blueComponent  * factor, 1.0)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: srgb.alphaComponent)
    }
}
