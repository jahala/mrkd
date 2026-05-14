import XCTest
@testable import mrkd

final class FragmentLinkHandlerTests: XCTestCase {

    func testSlugifyLowercases() {
        XCTAssertEqual(FragmentLinkHandler.slugify("Hello"), "hello")
    }

    func testSlugifyReplacesSpacesWithHyphens() {
        XCTAssertEqual(FragmentLinkHandler.slugify("Hello World"), "hello-world")
    }

    func testSlugifyDropsPunctuation() {
        XCTAssertEqual(FragmentLinkHandler.slugify("Foo: Bar!"), "foo-bar")
    }

    func testSlugifyCollapsesRunsOfWhitespace() {
        XCTAssertEqual(FragmentLinkHandler.slugify("a   b"), "a-b")
    }

    func testSlugifyKeepsUnderscoresAndHyphens() {
        XCTAssertEqual(FragmentLinkHandler.slugify("snake_case-and-kebab"), "snake_case-and-kebab")
    }

    func testSlugifyIsIdempotent() {
        let once = FragmentLinkHandler.slugify("My Heading 1.0")
        let twice = FragmentLinkHandler.slugify(once)
        XCTAssertEqual(once, twice)
    }

    func testResolveMatchesByText() {
        let entries = [
            TOCEntry(level: 1, text: "Quick Start", location: 0),
            TOCEntry(level: 2, text: "Installation Notes", location: 100),
        ]
        let match = FragmentLinkHandler.resolve(fragment: "installation-notes", in: entries)
        XCTAssertEqual(match?.location, 100)
    }

    func testResolveReturnsNilWhenNoMatch() {
        let entries = [TOCEntry(level: 1, text: "Intro", location: 0)]
        XCTAssertNil(FragmentLinkHandler.resolve(fragment: "missing", in: entries))
    }
}
