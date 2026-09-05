import XCTest
import AppKit
@testable import mrkd

/// Exercises the drawing itself by rasterising the view, so a bar that is
/// computed correctly but never painted (wrong opacity, wrong colour, rect
/// off the view) still fails.
@MainActor
final class ChangedBlockGutterViewTests: XCTestCase {

    private let barRect = NSRect(x: 86, y: 100, width: 3, height: 40)

    private func makeView() -> ChangedBlockGutterView {
        ChangedBlockGutterView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    }

    /// Rasterise `rect` and read the pixel under `point`.
    ///
    /// Both are in the view's (flipped) coordinate space, and the captured
    /// rect is deliberately wider than the bar: sampling only the bar's own
    /// rect would let a `draw` that floods its whole dirty rect go unnoticed,
    /// because the flood would be clipped to the sample.
    private func colour(of view: NSView, capturing rect: NSRect, at point: NSPoint) -> NSColor? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: rep)
        let scaleX = CGFloat(rep.pixelsWide) / rect.width
        let scaleY = CGFloat(rep.pixelsHigh) / rect.height
        let x = Int((point.x - rect.minX) * scaleX)
        let y = Int((point.y - rect.minY) * scaleY)
        guard x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh else { return nil }
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
    }

    /// A strip spanning the gutter *and* the article, so one rasterisation
    /// shows both what is painted and what is left alone.
    private var strip: NSRect { NSRect(x: 70, y: 100, width: 130, height: 40) }
    private var insideBar: NSPoint { NSPoint(x: 87.5, y: 120) }
    private var overTheArticle: NSPoint { NSPoint(x: 160, y: 120) }

    func testFlashPaintsTheGivenColourInsideTheBar() throws {
        let view = makeView()
        let accent = NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        view.flash([barRect], color: accent)

        guard let painted = colour(of: view, capturing: strip, at: insideBar) else {
            return XCTFail("could not rasterise the gutter")
        }
        XCTAssertGreaterThan(painted.alphaComponent, 0.5, "the bar should be painted, not blank")
        XCTAssertEqual(painted.redComponent, 0.2, accuracy: 0.08)
        XCTAssertEqual(painted.greenComponent, 0.6, accuracy: 0.08)
        XCTAssertEqual(painted.blueComponent, 0.9, accuracy: 0.08)
    }

    /// The accent lives in the margin. Anything painted over the article
    /// would sit on top of the text.
    func testNothingIsPaintedOutsideTheBar() throws {
        let view = makeView()
        view.flash([barRect], color: .systemPink)

        guard let painted = colour(of: view, capturing: strip, at: overTheArticle) else {
            return XCTFail("could not rasterise the gutter")
        }
        XCTAssertEqual(
            painted.alphaComponent, 0, accuracy: 0.01,
            "the article area must be left untouched, not flooded"
        )
    }

    func testClearStopsPainting() throws {
        let view = makeView()
        view.flash([barRect], color: .systemPink)
        view.clear()

        XCTAssertTrue(view.accentBars.isEmpty)
        guard let painted = colour(of: view, capturing: strip, at: insideBar) else {
            return XCTFail("could not rasterise the gutter")
        }
        XCTAssertEqual(painted.alphaComponent, 0, accuracy: 0.01)
    }

    /// The accent is a brief signal, not a permanent mark: it must take
    /// itself away. Real elapsed time, no injected clock.
    func testAccentFadesAwayWithinAFewSeconds() {
        let view = makeView()
        view.flash([barRect], color: .systemPink)
        XCTAssertFalse(view.accentBars.isEmpty, "the accent should be up immediately")

        let faded = expectation(description: "accent faded away")
        let poll = Timer(timeInterval: 0.05, repeats: true) { timer in
            if view.accentBars.isEmpty {
                timer.invalidate()
                faded.fulfill()
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        wait(for: [faded], timeout: 5)
        poll.invalidate()
    }
}
