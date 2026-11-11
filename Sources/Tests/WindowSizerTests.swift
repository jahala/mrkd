import XCTest
@testable import mrkd

/// A new window keeps the golden-ratio size, but opens wide enough for the
/// contents sidebar whenever the screen has room for that.
final class WindowSizerTests: XCTestCase {

    private func size(_ visible: NSSize, _ readingWidth: ReadingWidth = .standard) -> NSSize {
        WindowSizer.defaultSize(visible: visible, readingWidth: readingWidth)
    }

    private let laptop = NSSize(width: 1728, height: 989)
    private let bigMonitor = NSSize(width: 2560, height: 1415)

    func testALaptopWindowOpensWideEnoughForTheSidebar() {
        // The golden ratio alone gives 1068 wide, which hides the sidebar.
        XCTAssertEqual(size(laptop), NSSize(width: 1280, height: 791))
    }

    func testABigScreenKeepsTheGoldenRatioSize() {
        XCTAssertEqual(size(bigMonitor), NSSize(width: 1582, height: 978))
    }

    func testTheSidebarWidthFollowsTheReadingWidth() {
        XCTAssertEqual(size(laptop, .narrow), NSSize(width: 1120, height: 692))
        XCTAssertEqual(size(laptop, .wide), NSSize(width: 1520, height: 939))
    }

    /// Full Window never shows the sidebar, so there is nothing to widen for.
    func testFullWindowKeepsTheGoldenRatioSize() {
        XCTAssertEqual(size(laptop, .fullWindow), NSSize(width: 1068, height: 660))
    }

    func testAScreenTooNarrowForTheSidebarKeepsTheGoldenRatioSize() {
        XCTAssertEqual(size(NSSize(width: 1024, height: 700)), NSSize(width: 633, height: 391))
    }

    func testTheWindowNeverOutgrowsTheScreen() {
        let small = NSSize(width: 1280, height: 775)
        let result = size(small)
        XCTAssertLessThanOrEqual(result.width, small.width)
        XCTAssertLessThanOrEqual(result.height, small.height)
    }

    /// The sizer and the view decide with the same rule: every window opened
    /// wide enough for the sidebar really shows it.
    func testTheSidebarShowsInEveryWindowSizedForIt() {
        for screen in [laptop, bigMonitor, NSSize(width: 1440, height: 875)] {
            for readingWidth in [ReadingWidth.narrow, .standard, .wide] {
                let width = size(screen, readingWidth).width
                guard let needed = ColumnLayout.narrowestViewShowingSidebar(readingWidth: readingWidth),
                      needed <= screen.width else { continue }
                XCTAssertTrue(
                    ColumnLayout(viewWidth: width, readingWidth: readingWidth).showsSidebar,
                    "\(readingWidth) on \(screen)"
                )
            }
        }
    }
}
