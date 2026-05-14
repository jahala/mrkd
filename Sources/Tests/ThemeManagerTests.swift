import XCTest
@testable import mrkd

@MainActor
final class ThemeManagerTests: XCTestCase {

    /// Each test mutates the live CFPreferences plist so we have to clean
    /// up. Save the values before each test, restore after.
    private var savedTheme: String?
    private var savedFontSize: Double?

    override func setUp() async throws {
        savedTheme = CFPreferencesCopyAppValue("selectedTheme" as CFString, "com.mrkd.app" as CFString) as? String
        savedFontSize = CFPreferencesCopyAppValue("fontSize" as CFString, "com.mrkd.app" as CFString) as? Double
    }

    override func tearDown() async throws {
        if let savedTheme {
            CFPreferencesSetAppValue("selectedTheme" as CFString, savedTheme as CFString, "com.mrkd.app" as CFString)
        } else {
            CFPreferencesSetAppValue("selectedTheme" as CFString, nil, "com.mrkd.app" as CFString)
        }
        if let savedFontSize {
            CFPreferencesSetAppValue("fontSize" as CFString, savedFontSize as CFPropertyList, "com.mrkd.app" as CFString)
        } else {
            CFPreferencesSetAppValue("fontSize" as CFString, nil, "com.mrkd.app" as CFString)
        }
        CFPreferencesAppSynchronize("com.mrkd.app" as CFString)
    }

    func testSelectedThemeNameFallsBackToDefaultWhenUnset() {
        CFPreferencesSetAppValue("selectedTheme" as CFString, nil, "com.mrkd.app" as CFString)
        CFPreferencesAppSynchronize("com.mrkd.app" as CFString)
        XCTAssertEqual(ThemeManager.shared.selectedThemeName, "Default")
    }

    func testSelectedThemeNameReadsCFPreferencesValue() {
        CFPreferencesSetAppValue(
            "selectedTheme" as CFString,
            "Catppuccin Mocha" as CFString,
            "com.mrkd.app" as CFString
        )
        CFPreferencesAppSynchronize("com.mrkd.app" as CFString)
        XCTAssertEqual(ThemeManager.shared.selectedThemeName, "Catppuccin Mocha")
    }

    func testFontSizeFallsBackTo13ptWhenUnset() {
        CFPreferencesSetAppValue("fontSize" as CFString, nil, "com.mrkd.app" as CFString)
        CFPreferencesAppSynchronize("com.mrkd.app" as CFString)
        XCTAssertEqual(ThemeManager.shared.fontSize, 13.0)
    }

    func testFontSizeReadsCFPreferencesValue() {
        CFPreferencesSetAppValue(
            "fontSize" as CFString,
            16.0 as CFPropertyList,
            "com.mrkd.app" as CFString
        )
        CFPreferencesAppSynchronize("com.mrkd.app" as CFString)
        XCTAssertEqual(ThemeManager.shared.fontSize, 16.0)
    }

    func testCurrentThemeRespectsSelectedName() {
        CFPreferencesSetAppValue(
            "selectedTheme" as CFString,
            "Snazzy" as CFString,
            "com.mrkd.app" as CFString
        )
        CFPreferencesAppSynchronize("com.mrkd.app" as CFString)
        XCTAssertEqual(ThemeManager.shared.currentTheme.name, "Snazzy")
    }
}
