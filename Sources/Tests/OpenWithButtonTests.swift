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

    func testAnEmptyListSaysSo() {
        let menu = OpenWithButton.menu(listing: [])
        XCTAssertEqual(menu.items.map(\.title), ["No applications available"])
        XCTAssertEqual(menu.items.first?.isEnabled, false)
    }
}
