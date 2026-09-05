import AppKit

/// Translates the active mrkd theme into the colours merman draws diagrams in.
///
/// A diagram is part of the prose, not a screenshot pasted into it — a white
/// flowchart in a Catppuccin document reads as a bug. merman has a first-class
/// host-theming API for exactly this: a small set of named *roles* which it
/// compiles into the engine's site config. The roles fall back to one another
/// on its side (`surface-alt` to `surface`, `line` to `border`, notes and
/// sequence actors to the surfaces), so naming eight of them themes every
/// diagram family rather than thirty mermaid variables.
///
/// This is deliberately a pure function of the theme. It is what makes the
/// mapping testable without a renderer, and it makes the payload itself a
/// sound cache key: two requests that produce the same JSON produce the same
/// pixels, and an edited custom theme misses the cache even though its name
/// did not change.
enum MermaidThemePayload {

    /// The theme payload for `theme`, as the JSON the Rust shim decodes.
    ///
    /// Empty only if the payload could not be encoded, which the renderer
    /// then rejects — a diagram with no theme would be worse than none.
    static func json(for theme: Theme) -> String {
        let payload: [String: Any] = [
            "appearance": theme.isDark ? "dark" : "light",
            // The document's own body font. The renderer is handed mrkd's
            // bundled font files alongside this payload (`BundledFonts`), so
            // a family it ships — Inter, Literata, Geist — resolves to the
            // same face the prose is set in. `sans-serif` after it for the
            // families it does not: a custom theme can name anything, and a
            // named generic falls back to the system sans rather than to
            // whichever face the database happens to reach first.
            "fontFamily": "\(theme.fontFamily), sans-serif",
            "fontSize": "\(Int(theme.bodyFontSize.rounded()))px",
            "roles": roles(for: theme),
        ]
        // Sorted keys so the same theme always produces the same payload —
        // the diagram cache is keyed on this string, and an unstable key
        // would re-rasterise every diagram on every live reload.
        guard let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return "" }
        return json
    }

    /// The theme's colours under merman's role names.
    static func roles(for theme: Theme) -> [String: String] {
        // Theme colours are often semi-transparent (code and table
        // backgrounds usually are) or dynamic system colours. merman wants
        // plain CSS, so everything is composited onto the document background
        // first, and the background itself onto opaque black or white.
        let base = theme.isDark ? Self.opaqueBlack : Self.opaqueWhite
        let canvas = flatten(theme.backgroundColor, over: base)
        // The colour mrkd already uses for a raised block of content. A
        // diagram node is the same idea, so it gets the same fill.
        let surface = flatten(theme.codeBackgroundColor, over: canvas)

        func role(_ color: NSColor) -> String {
            hex(flatten(color, over: canvas))
        }

        return [
            "canvas": hex(canvas),
            // Set explicitly even though merman falls back to the canvas for
            // it. The box behind an edge label exists only to break the edge
            // line where the text crosses it, so it has to be the document's
            // own colour — any other value and it reads as a rectangle drawn
            // round the label. merman is a pinned pre-1.0 alpha and its role
            // fallbacks are free to change; this says what mrkd needs rather
            // than inheriting it.
            "edge-label-background": hex(canvas),
            "surface": hex(surface),
            // Notes, sequence actors and activations sit above the nodes, and
            // clusters recede behind them. Both are derived from the
            // canvas-to-surface axis rather than from the table colours: those
            // are the code background at a different alpha, so for a theme
            // whose code background is translucent they move away from the
            // canvas and for one whose background is opaque they move toward
            // it. Keying off them made a sequence diagram's actors far lighter
            // than the flowchart nodes in the same document.
            "surface-alt": hex(blend(canvas, toward: surface, by: 1.6)),
            "surface-muted": hex(blend(canvas, toward: surface, by: 0.5)),
            "text": role(theme.textColor),
            "subtle-text": role(theme.blockquoteColor),
            "border": role(theme.tableBorderColor),
            // Edges in the theme's signature colour. Arrows are the one part
            // of a diagram that should read as structure rather than as
            // content, and the accent is what mrkd already uses to say
            // "this line means something".
            "line": role(theme.accentColor),
            "error": role(theme.admonitionColor(type: .caution)),
            "warning": role(theme.admonitionColor(type: .warning)),
            "success": role(theme.admonitionColor(type: .tip)),
        ]
    }

    /// A colour `factor` of the way from `base` to `target`, carrying on past
    /// `target` when `factor` is greater than 1 and clamping at the ends.
    ///
    /// Both arguments must already be opaque. This is how the diagram's
    /// secondary surfaces stay in the same family as the primary one in every
    /// theme, light or dark, rather than depending on which direction a
    /// particular theme's alpha happens to move.
    static func blend(_ base: NSColor, toward target: NSColor, by factor: CGFloat) -> NSColor {
        let from = base.usingColorSpace(.sRGB) ?? opaqueBlack
        let to = target.usingColorSpace(.sRGB) ?? opaqueWhite
        func mix(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
            min(max(start + (end - start) * factor, 0), 1)
        }
        return NSColor(
            srgbRed: mix(from.redComponent, to.redComponent),
            green: mix(from.greenComponent, to.greenComponent),
            blue: mix(from.blueComponent, to.blueComponent),
            alpha: 1
        )
    }

    /// Composites `color` over `background`, producing an opaque colour.
    static func flatten(_ color: NSColor, over background: NSColor) -> NSColor {
        let top = color.usingColorSpace(.sRGB) ?? opaqueBlack
        let bottom = background.usingColorSpace(.sRGB) ?? opaqueWhite
        let alpha = top.alphaComponent
        func mix(_ over: CGFloat, _ under: CGFloat) -> CGFloat {
            over * alpha + under * (1 - alpha)
        }
        return NSColor(
            srgbRed: mix(top.redComponent, bottom.redComponent),
            green: mix(top.greenComponent, bottom.greenComponent),
            blue: mix(top.blueComponent, bottom.blueComponent),
            alpha: 1
        )
    }

    /// Formats a colour as `#RRGGBB`.
    static func hex(_ color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? opaqueBlack
        func channel(_ value: CGFloat) -> Int {
            // Extended-range sRGB holds components outside 0…1, and
            // "#1G0000" is not a colour merman will accept.
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X",
            channel(srgb.redComponent),
            channel(srgb.greenComponent),
            channel(srgb.blueComponent)
        )
    }

    /// Stand-ins for a colour with no sRGB form — a pattern colour. Fixed
    /// values rather than `NSColor.black`/`.white`, which are catalog colours
    /// and would reintroduce the same conversion question.
    private static let opaqueBlack = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private static let opaqueWhite = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
}
