import XCTest
import AppKit
@testable import mrkd

/// Real SwaTex layout and real bitmaps — nothing here is stubbed. The
/// assertions are about geometry and pixels, which is the only way to tell
/// a rendered formula from an empty box.
final class MathRendererTests: XCTestCase {

    // MARK: - Pixel helpers

    /// RGBA bytes of an image, redrawn into a known sRGB context so the
    /// layout of the samples is not at the mercy of the source bitmap.
    private func rgba(of image: NSImage) -> (width: Int, height: Int, bytes: [UInt8])? {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, bytes)
    }

    private func inkedPixelCount(_ image: NSImage) -> Int {
        guard let (width, height, bytes) = rgba(of: image) else { return 0 }
        var count = 0
        for pixel in 0..<(width * height) where bytes[pixel * 4 + 3] > 32 {
            count += 1
        }
        return count
    }

    /// Average colour of the inked pixels, ignoring the transparent ground.
    private func inkColor(_ image: NSImage) -> (r: Double, g: Double, b: Double)? {
        guard let (width, height, bytes) = rgba(of: image) else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for pixel in 0..<(width * height) where bytes[pixel * 4 + 3] > 128 {
            r += Double(bytes[pixel * 4])
            g += Double(bytes[pixel * 4 + 1])
            b += Double(bytes[pixel * 4 + 2])
            n += 1
        }
        guard n > 0 else { return nil }
        return (r / n, g / n, b / n)
    }

    private func pixelSize(of image: NSImage) -> (width: Int, height: Int)? {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        return (cgImage.width, cgImage.height)
    }

    // MARK: - Layout

    func testLayoutOfAParseableFormula() throws {
        let layout = try XCTUnwrap(MathRenderer.layout(latex: "E = mc^2", isDisplay: false, fontSize: 13))
        XCTAssertGreaterThan(layout.size.width, 0)
        XCTAssertGreaterThan(layout.size.height, 0)
        XCTAssertGreaterThan(layout.baselineFromTop, 0)
        XCTAssertLessThanOrEqual(layout.baselineFromTop, layout.size.height)
    }

    func testLayoutRejectsAFormulaSwaTexCannotParse() {
        XCTAssertNil(MathRenderer.layout(latex: "\\frac{1}{", isDisplay: false, fontSize: 13))
    }

    func testLayoutScalesWithFontSize() throws {
        let small = try XCTUnwrap(MathRenderer.layout(latex: "x + y", isDisplay: false, fontSize: 12))
        let large = try XCTUnwrap(MathRenderer.layout(latex: "x + y", isDisplay: false, fontSize: 24))
        XCTAssertEqual(large.size.width / small.size.width, 2, accuracy: 0.25)
        XCTAssertGreaterThan(large.size.height, small.size.height)
    }

    /// Display style puts the limits of a sum above and below it; text
    /// style tucks them beside it, so the display form is half again as
    /// tall. The margin matters: display math is also drawn with a couple
    /// of points more padding, and merely being *taller* would be
    /// satisfied by that padding alone even if the style were ignored.
    func testDisplayStyleStacksTheLimitsOfASum() throws {
        let inline = try XCTUnwrap(
            MathRenderer.layout(latex: "\\sum_{i=1}^{n} i", isDisplay: false, fontSize: 13))
        let display = try XCTUnwrap(
            MathRenderer.layout(latex: "\\sum_{i=1}^{n} i", isDisplay: true, fontSize: 13))
        XCTAssertGreaterThan(
            display.size.height, inline.size.height * 1.5,
            "the limits are beside the sum, not above and below it"
        )
    }

    /// The attachment sits so that the formula's own baseline lands on the
    /// surrounding text's baseline: the part below the baseline hangs down.
    func testAttachmentBoundsDropTheFormulaOntoTheTextBaseline() throws {
        let layout = try XCTUnwrap(MathRenderer.layout(latex: "x_1", isDisplay: false, fontSize: 13))
        let bounds = layout.attachmentBounds
        XCTAssertEqual(bounds.size, layout.size)
        XCTAssertEqual(bounds.origin.y, -(layout.size.height - layout.baselineFromTop), accuracy: 0.001)
        XCTAssertLessThan(bounds.origin.y, 0, "a subscript hangs below the baseline")
    }

    // MARK: - Rendering

    func testRenderProducesAnInkedBitmapOfTheLaidOutSize() throws {
        let rendered = try XCTUnwrap(
            MathRenderer.image(latex: "E = mc^2", isDisplay: false, fontSize: 20,
                               color: .black, scale: 2))
        XCTAssertEqual(rendered.image.size.width, rendered.layout.size.width, accuracy: 0.5)
        XCTAssertEqual(rendered.image.size.height, rendered.layout.size.height, accuracy: 0.5)
        XCTAssertGreaterThan(inkedPixelCount(rendered.image), 50,
                             "a rendered formula is not a blank box")
    }

    func testRenderHonoursTheBackingScaleFactor() throws {
        let atOne = try XCTUnwrap(
            MathRenderer.image(latex: "x", isDisplay: false, fontSize: 20, color: .black, scale: 1))
        let atThree = try XCTUnwrap(
            MathRenderer.image(latex: "x", isDisplay: false, fontSize: 20, color: .black, scale: 3))
        let one = try XCTUnwrap(pixelSize(of: atOne.image))
        let three = try XCTUnwrap(pixelSize(of: atThree.image))
        XCTAssertEqual(Double(three.width) / Double(one.width), 3, accuracy: 0.3)
        XCTAssertEqual(atOne.image.size.width, atThree.image.size.width, accuracy: 0.5,
                       "the point size is the same; only the pixel density changes")
    }

    func testRenderUsesTheColourItIsGiven() throws {
        let red = try XCTUnwrap(
            MathRenderer.image(latex: "x + y", isDisplay: false, fontSize: 30,
                               color: .systemRed, scale: 2))
        let blue = try XCTUnwrap(
            MathRenderer.image(latex: "x + y", isDisplay: false, fontSize: 30,
                               color: .systemBlue, scale: 2))
        let redInk = try XCTUnwrap(inkColor(red.image))
        let blueInk = try XCTUnwrap(inkColor(blue.image))
        XCTAssertGreaterThan(redInk.r, redInk.b + 40, "red formula must be red")
        XCTAssertGreaterThan(blueInk.b, blueInk.r + 40, "blue formula must be blue")
    }

    func testRenderRejectsAFormulaSwaTexCannotParse() {
        XCTAssertNil(MathRenderer.image(latex: "\\frac{1}{", isDisplay: false,
                                        fontSize: 13, color: .black, scale: 2))
    }
}
