import XCTest
import AppKit
@testable import mrkd

/// The cache is what keeps a live reload from re-rasterising every diagram in
/// the document every time an agent saves the file, so the tests are about
/// identity: a hit must hand back the very object it handed back before, and
/// anything that changes the pixels must miss.
final class DiagramAttachmentProviderTests: XCTestCase {

    private var provider: DiagramAttachmentProvider!

    private let flowchart = "flowchart TD\n  A[Start] --> B[Done]"

    override func setUp() {
        super.setUp()
        provider = DiagramAttachmentProvider()
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    /// Ask for a diagram and wait for the answer, reporting whether the
    /// answer arrived before the call returned.
    @discardableResult
    private func resolve(
        _ source: String,
        theme: Theme = CatppuccinMochaTheme(),
        scale: CGFloat = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (image: NSImage?, wasSynchronous: Bool) {
        var result: NSImage?
        var landed = false
        provider.image(for: source, theme: theme, scale: scale) { image in
            result = image
            landed = true
        }
        let synchronous = landed

        let deadline = Date().addingTimeInterval(15)
        while !landed && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(landed, "the provider never called back", file: file, line: line)
        return (result, synchronous)
    }

    // MARK: - Hits

    func testAFirstRequestRendersAsynchronouslyAndProducesABitmap() {
        let first = resolve(flowchart)

        XCTAssertFalse(first.wasSynchronous, "the renderer must not run on the caller's thread")
        XCTAssertNotNil(first.image)
        XCTAssertGreaterThan(first.image?.size.width ?? 0, 0)
    }

    func testARepeatRequestIsServedFromTheCacheBeforeItReturns() {
        let first = resolve(flowchart)
        let second = resolve(flowchart)

        XCTAssertTrue(second.wasSynchronous, "a cache hit must not go back to the renderer")
        XCTAssertTrue(
            first.image === second.image,
            "the same request produced a different bitmap object"
        )
    }

    // MARK: - Misses

    func testADifferentThemeRendersAgain() {
        let dark = resolve(flowchart, theme: CatppuccinMochaTheme())
        let light = resolve(flowchart, theme: GitHubLight())

        XCTAssertFalse(light.wasSynchronous, "a theme change must miss the cache")
        XCTAssertFalse(
            dark.image === light.image,
            "two themes shared one bitmap, so one of them is the wrong colour"
        )
    }

    func testADifferentScaleRendersAgain() {
        let atTwo = resolve(flowchart, scale: 2)
        let atOne = resolve(flowchart, scale: 1)

        XCTAssertFalse(atOne.wasSynchronous, "a scale change must miss the cache")
        XCTAssertFalse(atTwo.image === atOne.image)
    }

    func testADifferentSourceRendersAgain() {
        let first = resolve(flowchart)
        let second = resolve("flowchart TD\n  A[Start] --> B[Somewhere else]")

        XCTAssertFalse(second.wasSynchronous)
        XCTAssertFalse(first.image === second.image)
    }

    func testTheSameThemeRebuiltStillHits() {
        // Themes are values, not singletons — the controller hands over a
        // fresh one on every render. Keying on identity rather than on the
        // colours would miss every single time.
        let first = resolve(flowchart, theme: CatppuccinMochaTheme())
        let second = resolve(flowchart, theme: CatppuccinMochaTheme())

        XCTAssertTrue(second.wasSynchronous)
        XCTAssertTrue(first.image === second.image)
    }

    // MARK: - Failure

    func testAMalformedDiagramResolvesToNothingSoTheCallerCanShowTheSource() {
        let broken = resolve("flowchart TD\n  A[Unclosed --> B{{{")

        XCTAssertNil(broken.image)
    }

    /// Failures are cached as deliberately as successes: a document an agent
    /// is rewriting re-renders on every save, and re-discovering that a
    /// diagram is broken costs a full parse each time.
    func testAKnownBadDiagramIsNotReRenderedOnEveryRequest() {
        _ = resolve("flowchart TD\n  A[Unclosed --> B{{{")
        let second = resolve("flowchart TD\n  A[Unclosed --> B{{{")

        XCTAssertTrue(second.wasSynchronous, "a known-bad diagram was parsed a second time")
        XCTAssertNil(second.image)
    }
}
