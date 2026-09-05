import XCTest
import AppKit
@testable import mrkd

/// The Edit menu is the only way find is reachable in the app, so the
/// shortcuts it publishes are part of the feature, not decoration.
@MainActor
final class MenuBuilderTests: XCTestCase {

    private var savedWindowsMenu: NSMenu?
    private var savedHelpMenu: NSMenu?

    override func setUp() async throws {
        // Bring the shared application up before anything reads `NSApp`;
        // these tests can be the first thing to run in the process.
        _ = NSApplication.shared
        savedWindowsMenu = NSApp.windowsMenu
        savedHelpMenu = NSApp.helpMenu
    }

    override func tearDown() async throws {
        NSApp.windowsMenu = savedWindowsMenu
        NSApp.helpMenu = savedHelpMenu
    }

    private func editMenu() throws -> NSMenu {
        let mainMenu = MenuBuilder.buildMainMenu()
        let edit = mainMenu.items.compactMap(\.submenu).first { $0.title == "Edit" }
        return try XCTUnwrap(edit, "the main menu has no Edit menu")
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try XCTUnwrap(menu.items.first { $0.title == title }, "no \"\(title)\" item in the Edit menu")
    }

    func testFindItemsCarryTheStandardShortcuts() throws {
        let edit = try editMenu()

        let find = try item("Find...", in: edit)
        XCTAssertEqual(find.keyEquivalent, "f")
        XCTAssertEqual(find.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(find.action, #selector(MarkdownViewController.showFindBar(_:)))

        let next = try item("Find Next", in: edit)
        XCTAssertEqual(next.keyEquivalent, "g")
        XCTAssertEqual(next.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(next.action, #selector(MarkdownViewController.findNext(_:)))

        let previous = try item("Find Previous", in: edit)
        XCTAssertEqual(previous.keyEquivalent, "G")
        XCTAssertEqual(previous.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertEqual(previous.action, #selector(MarkdownViewController.findPrevious(_:)))

        let useSelection = try item("Use Selection for Find", in: edit)
        XCTAssertEqual(useSelection.keyEquivalent, "e")
        XCTAssertEqual(useSelection.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(useSelection.action, #selector(MarkdownViewController.useSelectionForFind(_:)))
    }

    func testFindItemsDispatchThroughTheResponderChain() throws {
        // A nil target means AppKit looks for the action on the first
        // responder's chain, which is how the view controller gets it.
        let edit = try editMenu()
        for title in ["Find...", "Find Next", "Find Previous", "Use Selection for Find"] {
            let menuItem = try item(title, in: edit)
            XCTAssertNil(menuItem.target, "\(title) must not be hard-targeted")
            let action = try XCTUnwrap(menuItem.action)
            XCTAssertTrue(
                MarkdownViewController.instancesRespond(to: action),
                "\(title) points at an action the view controller does not implement"
            )
        }
    }

    func testCopyAndSelectAllAreStillThere() throws {
        let edit = try editMenu()
        XCTAssertEqual(try item("Copy", in: edit).keyEquivalent, "c")
        XCTAssertEqual(try item("Select All", in: edit).keyEquivalent, "a")
    }
}
