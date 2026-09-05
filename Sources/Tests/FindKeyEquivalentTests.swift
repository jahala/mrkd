import XCTest
import AppKit
@testable import mrkd

/// The find shortcut table used by hosts with no menu bar (the Quick Look
/// preview extension).
final class FindKeyEquivalentTests: XCTestCase {

    func testCommandFOpensTheFindInterface() {
        XCTAssertEqual(
            FindKeyEquivalent.action(characters: "f", modifiers: [.command]),
            .showFindInterface
        )
    }

    func testCommandGGoesForwardAndCommandShiftGGoesBack() {
        XCTAssertEqual(
            FindKeyEquivalent.action(characters: "g", modifiers: [.command]),
            .nextMatch
        )
        // Shift-G arrives as an uppercase character.
        XCTAssertEqual(
            FindKeyEquivalent.action(characters: "G", modifiers: [.command, .shift]),
            .previousMatch
        )
    }

    func testCommandETakesTheSearchStringFromTheSelection() {
        XCTAssertEqual(
            FindKeyEquivalent.action(characters: "e", modifiers: [.command]),
            .setSearchString
        )
    }

    func testWithoutCommandNothingIsAFindShortcut() {
        XCTAssertNil(FindKeyEquivalent.action(characters: "f", modifiers: []))
        XCTAssertNil(FindKeyEquivalent.action(characters: "g", modifiers: [.shift]))
    }

    func testOtherModifiersRuleTheShortcutOut() {
        // Cmd-Option-F and Cmd-Control-G belong to something else.
        XCTAssertNil(FindKeyEquivalent.action(characters: "f", modifiers: [.command, .option]))
        XCTAssertNil(FindKeyEquivalent.action(characters: "g", modifiers: [.command, .control]))
    }

    func testCapsLockDoesNotRuleTheShortcutOut() {
        XCTAssertEqual(
            FindKeyEquivalent.action(characters: "F", modifiers: [.command, .capsLock]),
            .showFindInterface
        )
    }

    func testShiftedFAndEAreNotFindShortcuts() {
        // Only Find Previous has a shifted form; Cmd-Shift-F and Cmd-Shift-E
        // must stay available to whatever else wants them.
        XCTAssertNil(FindKeyEquivalent.action(characters: "F", modifiers: [.command, .shift]))
        XCTAssertNil(FindKeyEquivalent.action(characters: "E", modifiers: [.command, .shift]))
    }

    func testUnrelatedKeysAreNotFindShortcuts() {
        XCTAssertNil(FindKeyEquivalent.action(characters: "c", modifiers: [.command]))
        XCTAssertNil(FindKeyEquivalent.action(characters: "", modifiers: [.command]))
    }
}
