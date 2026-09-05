import XCTest
import AppKit
@testable import mrkd

final class ScrollAnchoringTests: XCTestCase {

    private func entry(_ level: Int, _ text: String, _ location: Int) -> TOCEntry {
        TOCEntry(level: level, text: text, location: location)
    }

    private func position(_ text: String, level: Int = 2, occurrence: Int = 0, y: CGFloat) -> HeadingPosition {
        HeadingPosition(key: HeadingKey(text: text, level: level, occurrence: occurrence), y: y)
    }

    // MARK: - keys

    func testKeysNumberRepeatedHeadingsByOccurrence() {
        let entries = [
            entry(1, "Notes", 0),
            entry(2, "Notes", 40),
            entry(2, "Notes", 80),
            entry(2, "Other", 120),
        ]
        XCTAssertEqual(ScrollAnchoring.keys(for: entries), [
            HeadingKey(text: "Notes", level: 1, occurrence: 0),
            HeadingKey(text: "Notes", level: 2, occurrence: 0),
            HeadingKey(text: "Notes", level: 2, occurrence: 1),
            HeadingKey(text: "Other", level: 2, occurrence: 0),
        ])
    }

    // MARK: - anchor

    func testAnchorsToTheLastHeadingAboveTheViewportTop() {
        let headings = [
            position("Intro", y: 0),
            position("Middle", y: 400),
            position("Later", y: 900),
        ]
        let anchor = ScrollAnchoring.anchor(headings: headings, viewportTop: 460, band: 0, maxScroll: 2000)
        XCTAssertEqual(anchor.heading, HeadingKey(text: "Middle", level: 2, occurrence: 0))
        XCTAssertEqual(anchor.offsetFromHeading, 60)
    }

    func testAnchorTakesTheHeadingExactlyAtTheViewportTop() {
        let headings = [position("Intro", y: 0), position("Middle", y: 400)]
        let anchor = ScrollAnchoring.anchor(headings: headings, viewportTop: 400, band: 0, maxScroll: 2000)
        XCTAssertEqual(anchor.heading?.text, "Middle")
        XCTAssertEqual(anchor.offsetFromHeading, 0)
    }

    /// Scrolled above the first heading — there is nothing to anchor to, so
    /// the anchor falls back to a proportion of the scrollable range.
    func testNoHeadingAboveViewportFallsBackToProportion() {
        let headings = [position("Intro", y: 500), position("Middle", y: 900)]
        let anchor = ScrollAnchoring.anchor(headings: headings, viewportTop: 250, band: 0, maxScroll: 1000)
        XCTAssertNil(anchor.heading)
        XCTAssertEqual(anchor.proportion, 0.25, accuracy: 0.0001)
    }

    func testDocumentWithNoHeadingsAnchorsProportionally() {
        let anchor = ScrollAnchoring.anchor(headings: [], viewportTop: 300, band: 0, maxScroll: 1200)
        XCTAssertNil(anchor.heading)
        XCTAssertEqual(anchor.proportion, 0.25, accuracy: 0.0001)
    }

    func testUnscrollableDocumentHasZeroProportion() {
        let anchor = ScrollAnchoring.anchor(headings: [], viewportTop: 0, band: 0, maxScroll: 0)
        XCTAssertNil(anchor.heading)
        XCTAssertEqual(anchor.proportion, 0)
    }

    /// The anchor also records a proportion when it has a heading, so a later
    /// reload that removes the heading still has something to fall back to.
    func testAnchorRecordsProportionAlongsideTheHeading() {
        let headings = [position("Middle", y: 400)]
        let anchor = ScrollAnchoring.anchor(headings: headings, viewportTop: 500, band: 0, maxScroll: 1000)
        XCTAssertEqual(anchor.heading?.text, "Middle")
        XCTAssertEqual(anchor.proportion, 0.5, accuracy: 0.0001)
    }

    // MARK: - offset

    /// The whole point: the heading moved because the text above it grew, and
    /// the reader lands the same distance below it, not at the same offset.
    func testRestoreFollowsTheHeadingToItsNewPosition() {
        let headings = [position("Intro", y: 0), position("Middle", y: 400)]
        let anchor = ScrollAnchoring.anchor(headings: headings, viewportTop: 460, band: 0, maxScroll: 2000)
        let restored = ScrollAnchoring.offset(restoring: anchor, headingY: 1150, maxScroll: 3000)
        XCTAssertEqual(restored, 1210)
    }

    func testRestoreWithoutTheHeadingUsesTheProportion() {
        let headings = [position("Middle", y: 400)]
        let anchor = ScrollAnchoring.anchor(headings: headings, viewportTop: 500, band: 0, maxScroll: 1000)
        // The edit deleted the "Middle" heading — nothing to follow.
        let restored = ScrollAnchoring.offset(restoring: anchor, headingY: nil, maxScroll: 800)
        XCTAssertEqual(restored, 400, accuracy: 0.0001)
    }

    func testRestoreClampsAboveTheTop() {
        let anchor = ScrollAnchor(
            heading: HeadingKey(text: "Middle", level: 2, occurrence: 0),
            offsetFromHeading: -50,
            proportion: 0
        )
        XCTAssertEqual(ScrollAnchoring.offset(restoring: anchor, headingY: 20, maxScroll: 1000), 0)
    }

    /// Deliberately not clamped to `maxScroll`: right after a re-render the
    /// caller's idea of the document height is the *previous* document's, so
    /// clamping here would haul the reader back up the page. The scroll view
    /// applies the real bound once it has laid the new text out.
    func testRestoreDoesNotClampToTheCallersIdeaOfTheDocumentHeight() {
        let anchor = ScrollAnchor(
            heading: HeadingKey(text: "Middle", level: 2, occurrence: 0),
            offsetFromHeading: 300,
            proportion: 0
        )
        XCTAssertEqual(ScrollAnchoring.offset(restoring: anchor, headingY: 900, maxScroll: 1000), 1200)
    }

    func testProportionalRestoreIntoAnUnscrollableDocumentIsZero() {
        let anchor = ScrollAnchor(
            heading: HeadingKey(text: "Middle", level: 2, occurrence: 0),
            offsetFromHeading: 60,
            proportion: 0.5
        )
        XCTAssertEqual(ScrollAnchoring.offset(restoring: anchor, headingY: nil, maxScroll: 0), 0)
    }

    /// Clicking a TOC entry parks its heading a fifth of the way down the
    /// viewport. That heading — not the one before it — is what the reader
    /// is looking at, so it is what the anchor has to hold on to.
    func testHeadingJustInsideTheViewportIsTheAnchor() {
        let headings = [position("Intro", y: 0), position("Target", y: 560)]
        let anchor = ScrollAnchoring.anchor(headings: headings, viewportTop: 500, band: 200, maxScroll: 4000)
        XCTAssertEqual(anchor.heading?.text, "Target")
        XCTAssertEqual(anchor.offsetFromHeading, -60)

        // The introduction above it doubles in length; the reader still sees
        // the Target heading in the same place on screen.
        XCTAssertEqual(
            ScrollAnchoring.offset(restoring: anchor, headingY: 1200, maxScroll: 6000),
            1140
        )
    }

    func testHeadingBeyondTheBandIsNotTaken() {
        let headings = [position("Intro", y: 0), position("Target", y: 800)]
        let anchor = ScrollAnchoring.anchor(headings: headings, viewportTop: 500, band: 200, maxScroll: 4000)
        XCTAssertEqual(anchor.heading?.text, "Intro")
        XCTAssertEqual(anchor.offsetFromHeading, 500)
    }
}
