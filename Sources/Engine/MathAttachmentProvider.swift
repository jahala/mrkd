import AppKit

/// A rendered formula: the bitmap, plus the bounds that put it on the
/// surrounding text's baseline.
final class MathImage {
    let image: NSImage
    let layout: MathLayout

    init(image: NSImage, layout: MathLayout) {
        self.image = image
        self.layout = layout
    }
}

/// Async formula rasterisation for `MarkdownViewController`, the sibling of
/// `ImageAttachmentProvider` behind the same deferred-attachment seam.
///
/// The cache is the point. An agent rewriting the open file re-renders the
/// document on every save, and almost every formula in it is unchanged; a
/// hit is served before the call returns, so nothing flickers and no work
/// is repeated. Anything that changes the pixels — the theme's body colour,
/// the zoom level, the display's backing scale — is part of the key, so a
/// change misses and re-renders.
final class MathAttachmentProvider {

    private let cache = NSCache<NSString, MathImage>()
    private let renderQueue = DispatchQueue(
        label: "com.mrkd.math",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var pressureObserver: NSObjectProtocol?

    init() {
        cache.countLimit = 512

        pressureObserver = NotificationCenter.default.addObserver(
            forName: MemoryMonitor.memoryPressureNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
            MathRenderer.clearCache()
        }
    }

    deinit {
        if let pressureObserver {
            NotificationCenter.default.removeObserver(pressureObserver)
        }
    }

    /// Render `span`, calling back on the main thread — or, on a cache hit,
    /// synchronously on the caller's thread before returning.
    ///
    /// `color` is resolved to sRGB here, on the calling thread, because a
    /// theme colour can be a dynamic system colour whose value depends on
    /// the appearance currently in effect.
    func image(
        for span: MathSpan,
        fontSize: CGFloat,
        color: NSColor,
        scale: CGFloat,
        completion: @escaping (MathImage?) -> Void
    ) {
        let resolved = color.usingColorSpace(.sRGB) ?? Self.fallbackColor
        let key = Self.cacheKey(
            span: span,
            fontSize: fontSize,
            color: resolved,
            scale: scale
        ) as NSString

        if let hit = cache.object(forKey: key) {
            completion(hit)
            return
        }

        renderQueue.async { [weak self] in
            let rendered = MathRenderer.image(
                latex: span.latex,
                isDisplay: span.isDisplay,
                fontSize: fontSize,
                color: resolved,
                scale: scale
            ).map { MathImage(image: $0.image, layout: $0.layout) }

            DispatchQueue.main.async {
                if let rendered {
                    self?.cache.setObject(rendered, forKey: key)
                }
                completion(rendered)
            }
        }
    }

    /// Stands in for a colour that has no sRGB form — a pattern colour.
    /// `MathRenderer` falls back to the same black, so the key still
    /// describes the pixels.
    private static let fallbackColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    private static func cacheKey(
        span: MathSpan,
        fontSize: CGFloat,
        color: NSColor,
        scale: CGFloat
    ) -> String {
        let rgba = [
            color.redComponent, color.greenComponent,
            color.blueComponent, color.alphaComponent,
        ]
        .map { String(format: "%.4f", $0) }
        .joined(separator: ",")
        return "\(span.isDisplay ? "display" : "inline")|\(fontSize)|\(rgba)|\(scale)|\(span.latex)"
    }
}
