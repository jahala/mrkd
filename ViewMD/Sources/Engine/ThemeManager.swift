import AppKit

@MainActor
final class ThemeManager: NSObject {

    // MARK: - Singleton

    static let shared = ThemeManager()

    // MARK: - Notifications

    static let themeDidChangeNotification = Notification.Name("ThemeDidChange")

    // MARK: - Theme Registry

    private func themeVariants(named name: String, fontSize: CGFloat, fontFamily: String, codeFontFamily: String) -> (light: Theme, dark: Theme)? {
        switch name {
        case "Default":
            return (light: DefaultTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily), dark: DefaultTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily))
        case "Solarized":
            return (light: SolarizedLight(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily), dark: SolarizedDark(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily))
        case "Monokai":
            return (light: MonokaiTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily), dark: MonokaiTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily))
        case "GitHub":
            return (light: GitHubLight(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily), dark: GitHubDark(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily))
        case "Dracula":
            return (light: DraculaTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily), dark: DraculaTheme(baseFontSize: fontSize, fontFamily: fontFamily, codeFontFamily: codeFontFamily))
        default:
            return nil
        }
    }

    // MARK: - Properties

    private var appearanceObservation: NSKeyValueObservation?

    var selectedThemeName: String {
        get {
            UserDefaults.standard.string(forKey: "selectedTheme") ?? "Default"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "selectedTheme")
            notifyThemeChange()
        }
    }

    var fontSize: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: "fontSize")
            return stored > 0 ? CGFloat(stored) : 13.0
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: "fontSize")
            notifyThemeChange()
        }
    }

    var fontFamily: String {
        get {
            UserDefaults.standard.string(forKey: "fontFamily") ?? "SF Mono"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "fontFamily")
            notifyThemeChange()
        }
    }

    var codeFontFamily: String {
        get {
            UserDefaults.standard.string(forKey: "codeFontFamily") ?? "JetBrains Mono"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "codeFontFamily")
            notifyThemeChange()
        }
    }

    var currentTheme: Theme {
        let themeName = selectedThemeName
        let currentFontSize = fontSize
        let currentFontFamily = fontFamily
        let currentCodeFontFamily = codeFontFamily

        guard let themeVariants = themeVariants(named: themeName, fontSize: currentFontSize, fontFamily: currentFontFamily, codeFontFamily: currentCodeFontFamily) else {
            return DefaultTheme(baseFontSize: currentFontSize, fontFamily: currentFontFamily, codeFontFamily: currentCodeFontFamily)
        }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = isDark ? themeVariants.dark : themeVariants.light

        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return HighContrastTheme(wrapping: theme)
        }

        return theme
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        observeAppearanceChanges()
        observeAccessibilityChanges()
    }

    // MARK: - Theme Management

    func availableThemeNames() -> [String] {
        return ["Default", "Solarized", "Monokai", "GitHub", "Dracula"].sorted()
    }

    func theme(named name: String, isDark: Bool) -> Theme? {
        let currentFontSize = fontSize
        let currentFontFamily = fontFamily
        let currentCodeFontFamily = codeFontFamily
        guard let themeVariants = themeVariants(named: name, fontSize: currentFontSize, fontFamily: currentFontFamily, codeFontFamily: currentCodeFontFamily) else { return nil }
        return isDark ? themeVariants.dark : themeVariants.light
    }

    // MARK: - Appearance Observation

    private func observeAppearanceChanges() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.notifyThemeChange()
            }
        }
    }

    private func observeAccessibilityChanges() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.notifyThemeChange()
            }
        }
    }

    private func notifyThemeChange() {
        NotificationCenter.default.post(name: Self.themeDidChangeNotification, object: self)
    }
}
