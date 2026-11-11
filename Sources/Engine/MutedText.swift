import AppKit

/// Text that sits back from the page but stays readable.
///
/// The colour is the theme's text colour faded toward the fill behind it, as
/// far as it can go while keeping WCAG AA contrast (4.5:1) against that fill.
/// It is worked out separately for light and dark appearance, because a
/// theme's colours can differ between the two.
enum MutedText {

    /// The least contrast text may have against its background (WCAG AA).
    static let minimumContrast: CGFloat = 4.5

    /// How far toward the fill the text may fade at most, so that muted text
    /// still reads as text when the theme has contrast to spare.
    static let maximumFade: CGFloat = 0.6

    static func color(text: NSColor, fill: NSColor, page: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved = text
            appearance.performAsCurrentDrawingAppearance {
                let pageColor = opaque(page, over: .white)
                let fillColor = opaque(fill, over: pageColor)
                let textColor = opaque(text, over: fillColor)
                resolved = mostFaded(textColor, toward: fillColor)
            }
            return resolved
        }
    }

    /// `text` faded toward `fill` in steps, stopping at the last step that
    /// still meets `minimumContrast`. Step zero is the text colour itself.
    static func mostFaded(_ text: NSColor, toward fill: NSColor) -> NSColor {
        var best = text
        var fade: CGFloat = 0.02
        while fade <= maximumFade + 0.0001 {
            let candidate = mix(text, fill, fade)
            guard contrast(candidate, fill) >= minimumContrast else { break }
            best = candidate
            fade += 0.02
        }
        return best
    }

    // MARK: - Colour arithmetic in sRGB

    static func opaque(_ color: NSColor, over base: NSColor) -> NSColor {
        let c = srgb(color), b = srgb(base)
        let a = c.alphaComponent
        return NSColor(
            srgbRed: c.redComponent * a + b.redComponent * (1 - a),
            green: c.greenComponent * a + b.greenComponent * (1 - a),
            blue: c.blueComponent * a + b.blueComponent * (1 - a),
            alpha: 1
        )
    }

    static func mix(_ x: NSColor, _ y: NSColor, _ amount: CGFloat) -> NSColor {
        let a = srgb(x), b = srgb(y)
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * amount,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount,
            alpha: 1
        )
    }

    /// WCAG contrast ratio between two opaque colours.
    static func contrast(_ x: NSColor, _ y: NSColor) -> CGFloat {
        let (lx, ly) = (luminance(x), luminance(y))
        return (max(lx, ly) + 0.05) / (min(lx, ly) + 0.05)
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        let c = srgb(color)
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    private static func srgb(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }
}
