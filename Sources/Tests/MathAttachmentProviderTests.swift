import XCTest
import AppKit
@testable import mrkd

/// The cache is what keeps a live reload from re-rasterising every formula
/// in the document on every keystroke an agent makes, so the tests are
/// about identity: a hit must hand back the very object it handed back
/// before, and anything that changes the pixels must miss.
final class MathAttachmentProviderTests: XCTestCase {

    private var provider: MathAttachmentProvider!

    override func setUp() {
        super.setUp()
        provider = MathAttachmentProvider()
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    /// Ask for a formula and wait for the answer, reporting whether the
    /// answer arrived before the call returned.
    @discardableResult
    private func resolve(
        _ latex: String,
        isDisplay: Bool = false,
        fontSize: CGFloat = 13,
        color: NSColor = .black,
        scale: CGFloat = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (image: MathImage?, wasSynchronous: Bool) {
        var result: MathImage?
        var landed = false
        var synchronous = false
        provider.image(
            for: MathSpan(latex: latex, isDisplay: isDisplay),
            fontSize: fontSize,
            color: color,
            scale: scale
        ) { image in
            result = image
            landed = true
        }
        synchronous = landed

        let deadline = Date().addingTimeInterval(6)
        while !landed && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(landed, "render never completed", file: file, line: line)
        return (result, synchronous)
    }

    private func pixelWidth(of image: NSImage) -> Int {
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)?.width ?? 0
    }

    func testFirstRenderIsAsynchronousAndProducesAnImage() {
        let (image, wasSynchronous) = resolve("E = mc^2")
        XCTAssertNotNil(image)
        XCTAssertFalse(wasSynchronous, "a cold render must not block the main thread")
    }

    func testRepeatedRequestIsServedFromTheCacheWithoutRerendering() {
        let first = resolve("E = mc^2").image
        let (second, wasSynchronous) = resolve("E = mc^2")
        XCTAssertTrue(wasSynchronous, "a cache hit must land before the call returns")
        XCTAssertNotNil(second)
        XCTAssertTrue(first === second, "a cache hit must hand back the same render")
    }

    func testFontSizeIsPartOfTheCacheKey() {
        let small = resolve("x + y", fontSize: 13).image
        let large = resolve("x + y", fontSize: 26).image
        XCTAssertFalse(small === large)
        XCTAssertGreaterThan(
            try! XCTUnwrap(large).layout.size.width,
            try! XCTUnwrap(small).layout.size.width
        )
    }

    func testColourIsPartOfTheCacheKey() {
        let dark = resolve("x + y", color: .black).image
        let light = resolve("x + y", color: .white).image
        XCTAssertNotNil(dark)
        XCTAssertNotNil(light)
        XCTAssertFalse(dark === light, "a theme change must not reuse the old colour")
    }

    func testBackingScaleIsPartOfTheCacheKey() throws {
        let low = try XCTUnwrap(resolve("x + y", scale: 1).image)
        let high = try XCTUnwrap(resolve("x + y", scale: 3).image)
        XCTAssertFalse(low === high)
        XCTAssertGreaterThan(pixelWidth(of: high.image), pixelWidth(of: low.image))
    }

    func testDisplayAndInlineStylesAreCachedSeparately() {
        let inline = resolve("\\sum_{i=1}^{n} i", isDisplay: false).image
        let display = resolve("\\sum_{i=1}^{n} i", isDisplay: true).image
        XCTAssertFalse(inline === display)
    }

    func testFormulaSwaTexCannotParseResolvesToNothing() {
        XCTAssertNil(resolve("\\frac{1}{").image)
    }
}
