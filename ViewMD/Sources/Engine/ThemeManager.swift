import AppKit

@MainActor
final class ThemeManager: NSObject {

    // MARK: - Singleton

    static let shared = ThemeManager()

    // MARK: - Notifications

    static let themeDidChangeNotification = Notification.Name("ThemeDidChange")

    // MARK: - Theme Registry

    private func themeVariants(named name: String, fontSize: CGFloat, fontFamily: String) -> (light: Theme, dark: Theme)? {
        switch name {
        case "Default":
            return (light: DefaultTheme(baseFontSize: fontSize, fontFamily: fontFamily), dark: DefaultTheme(baseFontSize: fontSize, fontFamily: fontFamily))
        case "Solarized":
            return (light: SolarizedLight(baseFontSize: fontSize, fontFamily: fontFamily), dark: SolarizedDark(baseFontSize: fontSize, fontFamily: fontFamily))
        case "Monokai":
            return (light: MonokaiTheme(baseFontSize: fontSize, fontFamily: fontFamily), dark: MonokaiTheme(baseFontSize: fontSize, fontFamily: fontFamily))
        case "GitHub":
            return (light: GitHubLight(baseFontSize: fontSize, fontFamily: fontFamily), dark: GitHubDark(baseFontSize: fontSize, fontFamily: fontFamily))
        case "Dracula":
            return (light: DraculaTheme(baseFontSize: fontSize, fontFamily: fontFamily), dark: DraculaTheme(baseFontSize: fontSize, fontFamily: fontFamily))
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

    nonisolated var fontFamily: String {
        get {
            UserDefaults.standard.string(forKey: "fontFamily") ?? "SF Mono"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "fontFamily")
            Task { @MainActor in
                notifyThemeChange()
            }
        }
    }

    var currentTheme: Theme {
        let themeName = selectedThemeName
        let currentFontSize = fontSize
        let currentFontFamily = fontFamily

        guard let themeVariants = themeVariants(named: themeName, fontSize: currentFontSize, fontFamily: currentFontFamily) else {
            return DefaultTheme(baseFontSize: currentFontSize, fontFamily: currentFontFamily)
        }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = isDark ? themeVariants.dark : themeVariants.light

        // Apply high contrast wrapper if needed
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
        guard let themeVariants = themeVariants(named: name, fontSize: currentFontSize, fontFamily: currentFontFamily) else { return nil }
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
