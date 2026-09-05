import AppKit
import CMermaid

/// Why a Mermaid source did not become a bitmap.
///
/// Every case leads to the same place in the UI — the styled code block, so
/// the reader sees their own source — but they are kept apart because
/// "you typed the diagram wrong" and "the renderer panicked" are different
/// facts about the world, and collapsing them would hide the second.
enum MermaidRenderFailure: Error, Equatable {
    /// Empty source, or a scale that is not a finite positive number.
    case invalidInput
    /// The source parsed but held no diagram.
    case noDiagram
    /// merman rejected the source, or the raster step failed.
    case renderFailed
    /// The renderer panicked and the unwind was caught at the C boundary.
    case rendererPanicked
    /// A bundled font file could not be read as a font. Distinct because it
    /// is a broken build rather than a broken diagram: every diagram in the
    /// document fails, and the reason is in the app bundle, not the markdown.
    case fontLoadFailed
    /// Bytes came back that are not a decodable image.
    case undecodableImage
    /// A status code this version of the shim does not know about.
    case unknown(Int32)

    init(status: Int32) {
        switch status {
        case MERMAID_ERR_INVALID_INPUT: self = .invalidInput
        case MERMAID_ERR_NO_DIAGRAM: self = .noDiagram
        case MERMAID_ERR_RENDER: self = .renderFailed
        case MERMAID_ERR_PANIC: self = .rendererPanicked
        case MERMAID_ERR_FONT: self = .fontLoadFailed
        default: self = .unknown(status)
        }
    }
}

/// Rasterises Mermaid diagrams through the merman-backed Rust library in
/// `Contents/Frameworks/libmermaid_shim.dylib`.
///
/// A linked library rather than a helper process, because the Quick Look
/// extension is sandboxed and cannot spawn one — and the app and the
/// extension share `MarkdownViewController`, so a helper would have worked in
/// one and silently not in the other.
///
/// This type is the whole Swift side of that boundary: source and theme in,
/// `NSImage` out, no merman vocabulary above it. The theme payload is built
/// by `MermaidThemePayload` and the caching happens in
/// `DiagramAttachmentProvider`.
enum MermaidRenderer {

    /// Rasterises `source` at `scale` device pixels per point, in the colours
    /// described by `themeJSON` (see `MermaidThemePayload`) and the fonts at
    /// `fontURLs` — normally `BundledFonts.urls`, mrkd's own typefaces, which
    /// the rasteriser cannot find for itself because they live in the app
    /// bundle rather than in a system font directory.
    ///
    /// Safe to call from any thread: the library builds a renderer per call
    /// and the one piece of shared state under it — the font database built
    /// from `fontURLs` and the system's — is behind its own lock.
    static func image(
        source: String,
        themeJSON: String,
        fontURLs: [URL],
        scale: CGFloat
    ) -> Result<NSImage, MermaidRenderFailure> {
        // An empty source is the one case worth catching here: merman would
        // call it a render failure, when what actually happened is that there
        // was nothing to render. The theme payload and the scale are checked
        // once, at the C boundary, which rejects both with the same
        // `.invalidInput` — duplicating those tests on this side would add a
        // branch no test could tell apart from the one below it.
        guard !source.isEmpty else { return .failure(.invalidInput) }

        // The font list crosses as JSON rather than as a C array of strings:
        // one NUL-terminated argument, one lifetime, and the same decoder the
        // theme payload already goes through on the other side.
        guard let fontData = try? JSONSerialization.data(withJSONObject: fontURLs.map(\.path)),
              let fontPathsJSON = String(data: fontData, encoding: .utf8)
        else { return .failure(.invalidInput) }

        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = source.withCString { source in
            themeJSON.withCString { themeJSON in
                fontPathsJSON.withCString { fontPathsJSON in
                    mermaid_render_png(
                        source, themeJSON, fontPathsJSON, Float(scale), &bytes, &length
                    )
                }
            }
        }

        guard status == MERMAID_OK else {
            return .failure(MermaidRenderFailure(status: status))
        }
        guard let bytes, length > 0 else {
            return .failure(.renderFailed)
        }
        defer { mermaid_free_png(bytes, length) }

        let data = Data(bytes: bytes, count: length)
        guard let representation = NSBitmapImageRep(data: data),
              representation.pixelsWide > 0, representation.pixelsHigh > 0
        else { return .failure(.undecodableImage) }

        // The PNG is in device pixels; the text system lays out in points.
        // Dividing here is what makes a Retina diagram occupy the same space
        // as the same diagram on a 1x display instead of twice as much.
        let size = NSSize(
            width: CGFloat(representation.pixelsWide) / scale,
            height: CGFloat(representation.pixelsHigh) / scale
        )
        representation.size = size
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return .success(image)
    }
}
