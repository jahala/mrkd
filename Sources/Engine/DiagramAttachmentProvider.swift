import AppKit

/// The outcome of rasterising one diagram: the bitmap, or the recorded fact
/// that this source cannot be drawn in this theme at this scale.
///
/// Failures are cached as deliberately as successes. Finding out that a
/// diagram is broken costs a full parse and layout, and a document an agent
/// is rewriting re-renders on every save — so remembering "this one doesn't
/// render" is what stops a typo in a flowchart from being re-discovered
/// several times a second.
final class DiagramRender {
    let image: NSImage?

    init(image: NSImage?) {
        self.image = image
    }
}

/// Async Mermaid rasterisation for `MarkdownViewController`, the third
/// provider behind the deferred-attachment seam alongside
/// `ImageAttachmentProvider` and `MathAttachmentProvider`.
final class DiagramAttachmentProvider {

    private let cache = NSCache<NSString, DiagramRender>()
    /// Serial, unlike the math provider's concurrent queue. A diagram is
    /// ~10 ms and can rasterise to several megabytes of bitmap; a document
    /// with twenty of them would otherwise put twenty full-size buffers in
    /// flight at once for no gain the reader can see.
    private let renderQueue = DispatchQueue(label: "com.mrkd.mermaid", qos: .userInitiated)
    private var pressureObserver: NSObjectProtocol?

    init() {
        cache.countLimit = 128

        pressureObserver = NotificationCenter.default.addObserver(
            forName: MemoryMonitor.memoryPressureNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    deinit {
        if let pressureObserver {
            NotificationCenter.default.removeObserver(pressureObserver)
        }
    }

    /// Render `source` in `theme` at `scale`, calling back on the main
    /// thread — or, on a cache hit, synchronously on the caller's thread
    /// before returning. `nil` means the diagram could not be rendered and
    /// the caller should show the source instead.
    ///
    /// The theme payload is built here, on the calling thread, because a
    /// theme colour can be a dynamic system colour whose value depends on the
    /// appearance currently in effect — which is not the renderer's thread.
    func image(
        for source: String,
        theme: Theme,
        scale: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) {
        let themeJSON = MermaidThemePayload.json(for: theme)
        // The payload carries every theme colour and the body font, so it is
        // the theme's entire contribution to the pixels. Two requests with
        // the same key cannot differ in output — which is more than keying on
        // the theme's name would give, since an edited custom theme keeps its
        // name.
        let key = "\(scale)|\(themeJSON)|\(source)" as NSString

        if let hit = cache.object(forKey: key) {
            completion(hit.image)
            return
        }

        renderQueue.async { [weak self] in
            let rendered = try? MermaidRenderer.image(
                source: source,
                themeJSON: themeJSON,
                scale: scale
            ).get()

            DispatchQueue.main.async {
                self?.cache.setObject(DiagramRender(image: rendered), forKey: key)
                completion(rendered)
            }
        }
    }
}
