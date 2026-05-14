import XCTest
@testable import mrkd

final class TOCBuilderTests: XCTestCase {

    func testEmptyStorageProducesEmptyArray() {
        let storage = NSAttributedString(string: "")
        XCTAssertEqual(TOCBuilder.build(from: storage), [])
    }

    func testStorageWithoutHeadingAttributesProducesEmptyArray() {
        let storage = NSAttributedString(string: "Plain paragraph with no headings.")
        XCTAssertEqual(TOCBuilder.build(from: storage), [])
    }

    func testExtractsSingleHeading() {
        let mutable = NSMutableAttributedString(string: "Heading\nBody.")
        mutable.addAttribute(
            .accessibilityHeadingLevel,
            value: 1,
            range: NSRange(location: 0, length: 7)
        )
        let entries = TOCBuilder.build(from: mutable)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].level, 1)
        XCTAssertEqual(entries[0].text, "Heading")
        XCTAssertEqual(entries[0].location, 0)
    }

    func testExtractsMultipleHeadingsInOrder() {
        let mutable = NSMutableAttributedString(string: "First\n\nbody\n\nSecond\n\nmore\n\nThird")
        mutable.addAttribute(.accessibilityHeadingLevel, value: 1, range: NSRange(location: 0, length: 5))
        mutable.addAttribute(.accessibilityHeadingLevel, value: 2, range: NSRange(location: 13, length: 6))
        mutable.addAttribute(.accessibilityHeadingLevel, value: 3, range: NSRange(location: 27, length: 5))

        let entries = TOCBuilder.build(from: mutable)
        XCTAssertEqual(entries.map(\.text), ["First", "Second", "Third"])
        XCTAssertEqual(entries.map(\.level), [1, 2, 3])
        XCTAssertEqual(entries.map(\.location), [0, 13, 27])
    }

    func testTrimsWhitespaceFromHeadingText() {
        let mutable = NSMutableAttributedString(string: "  Spaced Heading  \nbody")
        mutable.addAttribute(
            .accessibilityHeadingLevel,
            value: 1,
            range: NSRange(location: 0, length: 18)
        )
        let entries = TOCBuilder.build(from: mutable)
        XCTAssertEqual(entries.first?.text, "Spaced Heading")
    }
}
