import AppKit
import SwaTex
import SwaTexRender

/// A laid-out formula: how big it is, and where its baseline sits in it.
struct MathLayout: Equatable {
    let size: NSSize
    /// Distance from the top edge down to the formula's own baseline.
    let baselineFromTop: CGFloat

    /// Attachment bounds that drop the formula onto the surrounding text's
    /// baseline. `NSTextAttachment.bounds` is measured from that baseline,
    /// so the part of the formula below its own baseline — a subscript, the
    /// tail of an integral sign — has to hang below the origin.
    var attachmentBounds: NSRect {
        NSRect(
            x: 0,
            y: -(size.height - baselineFromTop),
            width: size.width,
            height: size.height
        )
    }
}

/// The whole of mrkd's dependency on SwaTex. Everything above this file
/// deals in `NSImage`, `NSColor` and `NSRect`.
///
/// Layout and rasterisation are separate on purpose. `MarkdownRenderer`
/// needs the size while it builds the attributed string on a background
/// queue, where the window's backing scale factor is not knowable; the
/// pixels are produced later, on the view side, at the scale the display
/// actually has.
enum MathRenderer {

    /// Breathing room around the glyphs so antialiased edges are not clipped
    /// by the edge of the bitmap. Small, because it is real space in the line.
    private static let inlinePadding: CGFloat = 1
    private static let displayPadding: CGFloat = 3

    /// Size and baseline of a formula, or nil if SwaTex cannot parse it.
    static func layout(latex: String, isDisplay: Bool, fontSize: CGFloat) -> MathLayout? {
        guard let list = displayList(latex: latex, isDisplay: isDisplay, color: .black) else {
            return nil
        }
        return measure(list, isDisplay: isDisplay, fontSize: fontSize)
    }

    /// Rasterise a formula at `scale` device pixels per point, in `color`.
    /// Nil if SwaTex cannot parse it.
    static func image(
        latex: String,
        isDisplay: Bool,
        fontSize: CGFloat,
        color: NSColor,
        scale: CGFloat
    ) -> (image: NSImage, layout: MathLayout)? {
        guard let list = displayList(
            latex: latex,
            isDisplay: isDisplay,
            color: swaTexColor(color)
        ) else { return nil }

        let layout = measure(list, isDisplay: isDisplay, fontSize: fontSize)
        guard let cgImage = ImageRenderer.image(
            for: list,
            options: options(isDisplay: isDisplay, fontSize: fontSize),
            displayScale: max(1, scale)
        ) else { return nil }

        return (NSImage(cgImage: cgImage, size: layout.size), layout)
    }

    // MARK: - SwaTex

    /// Parse and lay out, memoised process-wide by SwaTex's own cache: a
    /// re-render after a live reload re-asks for every formula in the
    /// document and almost all of them are unchanged.
    private static func displayList(
        latex: String,
        isDisplay: Bool,
        color: SwaTex.Color
    ) -> DisplayList? {
        try? SwaTexEngine.displayList(
            for: latex,
            style: isDisplay ? .display : .text,
            color: color,
            cache: .shared
        )
    }

    /// Drop every parsed formula. Called on memory pressure.
    static func clearCache() {
        FormulaCache.shared.removeAll()
    }

    private static func measure(
        _ list: DisplayList,
        isDisplay: Bool,
        fontSize: CGFloat
    ) -> MathLayout {
        let metrics = DisplayListRenderer.metrics(
            for: list,
            options: options(isDisplay: isDisplay, fontSize: fontSize)
        )
        return MathLayout(
            size: NSSize(width: metrics.width, height: metrics.height),
            baselineFromTop: metrics.baseline
        )
    }

    private static func options(isDisplay: Bool, fontSize: CGFloat) -> RenderOptions {
        RenderOptions(
            fontSize: fontSize,
            padding: isDisplay ? displayPadding : inlinePadding
        )
    }

    /// The theme's colour, resolved to sRGB components. Callers resolve
    /// dynamic system colours on the main thread before getting here.
    private static func swaTexColor(_ color: NSColor) -> SwaTex.Color {
        guard let srgb = color.usingColorSpace(.sRGB) else { return .black }
        return SwaTex.Color(
            r: Float(srgb.redComponent),
            g: Float(srgb.greenComponent),
            b: Float(srgb.blueComponent),
            a: Float(srgb.alphaComponent)
        )
    }
}
