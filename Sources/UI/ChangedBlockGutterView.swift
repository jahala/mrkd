import AppKit

/// Transient left-gutter accents marking the blocks a live reload changed.
///
/// Sits on top of the text view, in the same flipped coordinate space, and
/// scrolls with the document. It never takes a hit, so text selection and
/// link clicks pass straight through to the text view underneath.
///
/// The fade is driven by a timer rather than the animator proxy because the
/// text view is not layer-backed; making it so to animate an overlay would
/// change how the document itself is composited.
final class ChangedBlockGutterView: NSView {

    /// Width of the accent bar.
    private static let barWidth: CGFloat = 3
    /// Distance from the article's left text edge to the bar.
    private static let barInset: CGFloat = 14
    private static let holdDuration: TimeInterval = 1.4
    private static let fadeDuration: TimeInterval = 0.6
    private static let frameInterval: TimeInterval = 1.0 / 30

    /// The accents currently drawn, in text-view coordinates. Empty once
    /// the flash has faded.
    private(set) var accentBars: [NSRect] = []
    private var accent: NSColor = .clear
    private var opacity: CGFloat = 0
    private var fadeStartedAt: Date?
    private var timer: Timer?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Decoration, not content: VoiceOver has the document itself.
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    deinit {
        timer?.invalidate()
    }

    /// The bar to draw beside a run of text, given where the article's text
    /// begins horizontally.
    static func bar(besideTextRect rect: NSRect, textLeftEdge: CGFloat) -> NSRect {
        NSRect(
            x: textLeftEdge - barInset,
            y: rect.minY,
            width: barWidth,
            height: max(rect.height, barWidth)
        )
    }

    /// Show accents at `rects` (text-view coordinates), hold, then fade out.
    /// Calling it again restarts the whole cycle.
    func flash(_ rects: [NSRect], color: NSColor) {
        stopTimer()
        accentBars = rects
        accent = color
        opacity = rects.isEmpty ? 0 : 1
        fadeStartedAt = nil
        needsDisplay = true
        guard !rects.isEmpty else { return }
        schedule(after: Self.holdDuration, repeats: false) { $0.beginFade() }
    }

    /// Drop the accents immediately — used when a new render invalidates the
    /// rects these bars were measured against.
    func clear() {
        stopTimer()
        guard !accentBars.isEmpty || opacity > 0 else { return }
        accentBars = []
        opacity = 0
        needsDisplay = true
    }

    // MARK: - Fade

    private func beginFade() {
        fadeStartedAt = Date()
        schedule(after: Self.frameInterval, repeats: true) { $0.stepFade() }
    }

    private func stepFade() {
        guard let fadeStartedAt else { return }
        let progress = Date().timeIntervalSince(fadeStartedAt) / Self.fadeDuration
        if progress >= 1 {
            clear()
            return
        }
        // Ease out, so the accent lingers and then leaves quickly.
        let eased = 1 - progress
        opacity = CGFloat(eased * eased)
        needsDisplay = true
    }

    /// The timer holds no strong reference back, and stops itself if the view
    /// goes away — otherwise the repeating fade timer would outlive it and be
    /// retained by the run loop forever.
    private func schedule(
        after interval: TimeInterval,
        repeats: Bool,
        _ body: @escaping (ChangedBlockGutterView) -> Void
    ) {
        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            body(self)
        }
        // .common so the accent keeps fading while the user drags the scroller.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        fadeStartedAt = nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard opacity > 0, !accentBars.isEmpty else { return }
        accent.withAlphaComponent(opacity).setFill()
        let radius = Self.barWidth / 2
        for bar in accentBars where bar.intersects(dirtyRect) {
            NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()
        }
    }
}
