import XCTest
import AppKit
@testable import mrkd

final class OpenWithButtonTests: XCTestCase {

    func testTheButtonSaysOpenIn() {
        let button = OpenWithButton(fileURL: URL(fileURLWithPath: "/tmp/plan.md"))
        XCTAssertEqual(button.accessibilityLabel(), "Open in")
    }

    /// From macOS 27, AppKit hides menu item images unless an item asks for
    /// them. The app icons are how people find the app in this menu.
    func testEveryAppInTheMenuShowsItsIcon() {
        let apps = [URL(fileURLWithPath: "/System/Applications/TextEdit.app")]
        let menu = OpenWithButton.menu(listing: apps)

        XCTAssertEqual(menu.items.map(\.title), ["TextEdit"])
        XCTAssertEqual(menu.items.first?.representedObject as? URL, apps[0])
        XCTAssertNotNil(menu.items.first?.image)
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            XCTAssertEqual(menu.items.first?.preferredImageVisibility, .visible)
        }
        #endif
    }

    /// macOS lists every copy of an app it knows about: an old version, a
    /// build folder, a second download. The menu names each app once, the
    /// copy macOS lists first, and leaves out the app it is shown in.
    func testEachAppIsListedOnceAndThisAppNotAtAll() {
        let apps = [
            "/Applications/Xcode.app",
            "/Applications/mrkd.app",
            "/Users/me/Downloads/mrkd.app",
            "/Applications/TextEdit.app",
            "/Users/me/chrome/129/Google Chrome for Testing.app",
            "/Users/me/chrome/131/Google Chrome for Testing.app",
            "/Applications/Notes.app",
            "/Applications/Old Tool.app",
        ].map { URL(fileURLWithPath: $0) }
        let identifiers = [
            "Xcode": "com.apple.dt.Xcode",
            "mrkd": "com.mrkd.app",
            "TextEdit": "com.apple.TextEdit",
            "Google Chrome for Testing": "com.google.chrome.for.testing",
            "Notes": "com.apple.Notes",
        ]
        let listed = OpenWithButton.uniqueApps(
            apps,
            excluding: "com.mrkd.app",
            bundleIdentifier: { identifiers[$0.deletingPathExtension().lastPathComponent] }
        )
        XCTAssertEqual(listed.map(\.path), [
            "/Applications/Xcode.app",
            "/Applications/TextEdit.app",
            "/Users/me/chrome/129/Google Chrome for Testing.app",
            "/Applications/Notes.app",
            "/Applications/Old Tool.app",
        ])
    }

    /// In Quick Look the code runs inside the extension, whose identifier is
    /// not the app's. mrkd stays in the menu there, once: opening the file
    /// in mrkd is what a preview is for.
    func testQuickLookKeepsMrkdOnce() {
        let apps = ["/Applications/mrkd.app", "/Users/me/Downloads/mrkd.app"].map { URL(fileURLWithPath: $0) }
        let listed = OpenWithButton.uniqueApps(apps, excluding: "com.mrkd.app.QLPlugin", bundleIdentifier: { _ in "com.mrkd.app" })
        XCTAssertEqual(listed.map(\.path), ["/Applications/mrkd.app"])
    }

    func testAnEmptyListSaysSo() {
        let menu = OpenWithButton.menu(listing: [])
        XCTAssertEqual(menu.items.map(\.title), ["No applications available"])
        XCTAssertEqual(menu.items.first?.isEnabled, false)
    }
}
