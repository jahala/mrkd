import XCTest
@testable import mrkd

/// The arithmetic behind putting an in-flight search back on its match
/// after the document underneath it was replaced.
final class FindRestorationTests: XCTestCase {

    // MARK: - Locating matches

    func testMatchesFindsEveryOccurrenceInDocumentOrder() {
        let matches = FindRestoration.matches(of: "alpha", in: "alpha beta alpha gamma alpha")
        XCTAssertEqual(matches.map(\.location), [0, 11, 23])
        XCTAssertEqual(matches.map(\.length), [5, 5, 5])
    }

    func testMatchesIgnoresCaseTheWayTheFindBarDoes() {
        let matches = FindRestoration.matches(of: "target", in: "Target and TARGET and target")
        XCTAssertEqual(matches.map(\.location), [0, 11, 22])
    }

    func testMatchesDoNotOverlap() {
        // "aaaa" holds two "aa", not three: the second starts where the
        // first ended, as every find implementation counts them.
        XCTAssertEqual(FindRestoration.matches(of: "aa", in: "aaaa").map(\.location), [0, 2])
    }

    func testMatchesOfAnEmptyNeedleIsEmpty() {
        XCTAssertTrue(FindRestoration.matches(of: "", in: "anything at all").isEmpty)
    }

    func testMatchesOfAnAbsentNeedleIsEmpty() {
        XCTAssertTrue(FindRestoration.matches(of: "delta", in: "alpha beta gamma").isEmpty)
    }

    // MARK: - Choosing which match to land on

    func testRestoresToTheSameMatchAfterTheTextAboveItGrew() {
        // The reader was on the second "needle" at offset 30. A rewrite
        // pushed everything down 20 characters; the second occurrence is
        // still the one they were reading.
        let previous = FindMatch(text: "needle", location: 30)
        let grown = String(repeating: ".", count: 20) + "needle" + String(repeating: ".", count: 24) + "needle"
        XCTAssertEqual(FindRestoration.matches(of: "needle", in: grown).map(\.location), [20, 50])
        XCTAssertEqual(
            FindRestoration.restoredMatch(for: previous, in: grown),
            NSRange(location: 50, length: 6)
        )
    }

    func testRestoresToTheMatchExactlyAtThePreviousLocation() {
        let previous = FindMatch(text: "x", location: 4)
        XCTAssertEqual(
            FindRestoration.restoredMatch(for: previous, in: "a x b x c"),
            NSRange(location: 6, length: 1)
        )
        // Offset 2 is the first "x" itself — an unchanged reload must not
        // walk the reader forward to the next one.
        XCTAssertEqual(
            FindRestoration.restoredMatch(for: FindMatch(text: "x", location: 2), in: "a x b x c"),
            NSRange(location: 2, length: 1)
        )
    }

    func testRestoresToTheLastMatchWhenTheEditDeletedEverythingBelow() {
        let previous = FindMatch(text: "needle", location: 900)
        let shrunk = "needle at the top and needle again"
        XCTAssertEqual(
            FindRestoration.restoredMatch(for: previous, in: shrunk),
            NSRange(location: 22, length: 6)
        )
    }

    func testRestoreIsNilWhenTheMatchedTextIsGone() {
        let previous = FindMatch(text: "needle", location: 30)
        XCTAssertNil(FindRestoration.restoredMatch(for: previous, in: "nothing to find here"))
    }
}
