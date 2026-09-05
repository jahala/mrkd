import AppKit

final class MarkdownViewController: NSViewController {

    let fileURL: URL?
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var markdownContent: String = ""
    private var themeObserver: NSObjectProtocol?
    private var memoryPressureObserver: NSObjectProtocol?
    private let pipeline = RenderPipeline()
    private var openWithButton: OpenWithButton?
    private let textInteractionHandler = TextInteractionHandler()
    private var fileWatcher: FileWatcher?
    private var reloadBanner: ReloadBannerView?
    private var didCompleteInitialRender = false
    private var scrollAheadController: ScrollAheadController?
    private lazy var imageProvider = ImageAttachmentProvider(fileBaseURL: fileURL ?? URL(fileURLWithPath: NSTemporaryDirectory()))
    private let mathProvider = MathAttachmentProvider()
    private let diagramProvider = DiagramAttachmentProvider()
    private var renderGeneration = 0
    /// Set while a deferred-attachment re-walk is already queued, so a
    /// document with several unrenderable diagrams costs one pass, not one
    /// per diagram.
    private var isAttachmentRescanScheduled = false
    private var tocView: TOCFloatingView!
    private var scrollObserver: NSObjectProtocol?
    private var activeHeadingWork: DispatchWorkItem?
    private var gutterView: ChangedBlockGutterView!
    private var lastLaidOutArticleWidth: CGFloat = 0
    private(set) var findController: DocumentFindController!

    /// The source this controller rendered before the current one. A live
    /// reload diffs against it to work out which blocks changed.
    private(set) var previousMarkdownContent: String = ""

    /// True when a file change arrived while the user had text selected.
    /// Reloading would destroy the selection, so the reload waits until the
    /// selection clears.
    private(set) var isLiveReloadHeldBySelection = false

    /// True when the current selection was put there by a find action
    /// rather than by the reader. A match is not work in progress — it is
    /// restored across a re-render — so it must not hold a reload back.
    private var selectionBelongsToFind = false

    /// Handle the find shortcuts in the view hierarchy instead of leaving
    /// them to the Edit menu. Set by hosts that have no menu bar — the
    /// Quick Look preview extension.
    var handlesFindKeyEquivalents = false {
        didSet { applyFindKeyEquivalentHandling() }
    }

    /// Reading position captured just before a live reload, applied once the
    /// re-render lands. Non-nil only while a live reload is in flight.
    private var pendingReadingAnchor: ScrollAnchor?

    /// The match an active search was on before the text storage was
    /// replaced, to be re-found in the new text.
    private var pendingFindMatch: FindMatch?

    private lazy var reloadDebouncer = Debouncer(delay: Self.liveReloadDebounce) { [weak self] in
        self?.performLiveReload()
    }
    /// A save from an editor or an agent arrives as several filesystem events
    /// in a row. Waiting this long after the last one turns a burst into one
    /// render, and keeps the file from being read mid-write.
    private static let liveReloadDebounce: TimeInterval = 0.12
    private static let articleMaxWidth: CGFloat = 800
    private static let articleMinHorizontalPadding: CGFloat = 60
    private static let tocWidth: CGFloat = 200
    private static let tocRightMargin: CGFloat = 24
    private static let tocVisibilityThreshold: CGFloat = 1280
    /// How far into the viewport a heading can sit and still count as the one
    /// the reader is under. Shared by the TOC's active-entry highlight and by
    /// the live-reload reading anchor, so both agree on where "here" is.
    private static let activeHeadingBandFraction: CGFloat = 0.25

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    init(markdownString: String) {
        self.fileURL = nil
        self.markdownContent = markdownString
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = memoryPressureObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        activeHeadingWork?.cancel()
        pipeline.cancel()
        fileWatcher?.stop()
    }

    override func loadView() {
        let containerView = MarkdownContainerView()
        containerView.autoresizingMask = [.width, .height]

        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.autoresizingMask = [.width, .height]

        // TextKit 1 stack — TextKit 2 has layout failures with NSTextBlock
        // (used in code blocks and tables), causing "deferral block timed out"
        let textStorage = NSTextStorage()
        let layoutManager = CodeBorderLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 82, height: 40)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = textInteractionHandler
        textInteractionHandler.owner = self

        // Rides on the text view so the accents scroll with the document.
        gutterView = ChangedBlockGutterView(frame: .zero)
        textView.addSubview(gutterView)

        scrollView.documentView = textView
        scrollView.frame = containerView.bounds
        containerView.addSubview(scrollView)

        findController = DocumentFindController(textView: textView, scrollView: scrollView)

        // Add Open With button — on the container view, not the scroll view,
        // so it floats on top without interference from NSScrollView's internal layout.
        if let fileURL {
            let button = OpenWithButton(fileURL: fileURL)
            containerView.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
                button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12)
            ])

            button.alphaValue = 1
            openWithButton = button
        }

        tocView = TOCFloatingView()
        containerView.addSubview(tocView)
        tocView.onSelect = { [weak self] entry in
            self?.scrollToHeading(entry)
        }

        NSLayoutConstraint.activate([
            tocView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Self.tocRightMargin),
            tocView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 80),
            tocView.widthAnchor.constraint(equalToConstant: Self.tocWidth),
            // Definite bottom — not lessThanOrEqualTo. With a loose bottom
            // constraint and no intrinsic content size, AutoLayout collapses
            // the tocView height to fit just the header, leaving the inner
            // scrollView at 0pt tall. The main app happened to render anyway
            // because the window's autoresizing chain settled at a tall
            // value; the QL extension's hosting picks the minimum.
            tocView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -80),
        ])

        self.view = containerView
        applyFindKeyEquivalentHandling()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeThemeChanges()
        observeMemoryPressure()
        if fileURL != nil {
            loadMarkdownFile()
            setupFileWatcher()
        } else {
            renderLoadedContent()
        }
        setupKeyViewLoop()
        setupScrollAhead()
        setupAccessibilityRotors()
        setupActiveHeadingSync()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let container = textView.textContainer else { return }
        let windowW = view.bounds.width
        let articleW = min(Self.articleMaxWidth, windowW - 2 * Self.articleMinHorizontalPadding)
        let sideInset = max(Self.articleMinHorizontalPadding, (windowW - articleW) / 2)
        container.containerSize.width = articleW
        textView.textContainerInset = NSSize(width: sideInset, height: 40)
        textView.frame.size.width = windowW
        tocView.isHidden = view.bounds.width < Self.tocVisibilityThreshold

        // A width change re-wraps the text, so any accents drawn against the
        // old line rects now point at the wrong places.
        if articleW != lastLaidOutArticleWidth {
            lastLaidOutArticleWidth = articleW
            gutterView.clear()
        }
    }

    // MARK: - Theme Integration

    private func observeThemeChanges() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.themeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rerender()
        }
    }

    private func observeMemoryPressure() {
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: MemoryMonitor.memoryPressureNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Release the Highlightr JSC context — it will be lazily re-created
            MarkdownRenderer.clearHighlightrCache()
        }
    }

    private func applyThemeColors() {
        let theme = ThemeManager.shared.currentTheme
        textView.backgroundColor = theme.backgroundColor
        scrollView.backgroundColor = theme.backgroundColor
        view.layer?.backgroundColor = theme.backgroundColor.cgColor
        findController.applyTheme(theme)
    }

    private func rerender() {
        guard !markdownContent.isEmpty else { return }
        renderGeneration += 1
        gutterView.clear()
        let scrollPosition = scrollView.contentView.bounds.origin
        let theme = ThemeManager.shared.currentTheme
        // Re-rendering for a new theme or font size replaces the text
        // storage just as a reload does, and drops the selection with it.
        pendingFindMatch = findController.currentMatch()

        pipeline.render(markdown: markdownContent, theme: theme) { [weak self] result in
            guard let self = self else { return }
            self.textView.textStorage?.setAttributedString(result.attributedString)
            if let storage = self.textView.textStorage {
                self.tocView.entries = TOCBuilder.build(from: storage)
            }
            self.applyThemeColors()
            self.resolveDeferredAttachments()
            // Restore scroll position
            self.scrollView.contentView.scroll(to: scrollPosition)
            self.restorePendingFindMatch()
            self.scheduleActiveHeadingUpdate()
        }
    }

    // MARK: - File Loading

    private func renderLoadedContent() {
        renderGeneration += 1
        let theme = ThemeManager.shared.currentTheme
        pipeline.render(markdown: markdownContent, theme: theme) { [weak self] result in
            guard let self else { return }
            self.textView.textStorage?.setAttributedString(result.attributedString)
            self.applyThemeColors()
            self.resolveDeferredAttachments()
            self.notifyInitialRenderComplete()
        }
    }

    private func loadMarkdownFile() {
        guard let fileURL else { return }
        renderGeneration += 1
        let readResult = FileReader.read(url: fileURL)

        switch readResult {
        case .content(let content):
            previousMarkdownContent = markdownContent
            markdownContent = content
            let theme = ThemeManager.shared.currentTheme
            let tier = FileTierRouter.tier(for: fileURL)

            if tier == .small {
                // Tier 1: full immediate render
                pipeline.render(markdown: content, theme: theme) { [weak self] result in
                    guard let self = self else { return }
                    self.textView.textStorage?.setAttributedString(result.attributedString)
                    if let storage = self.textView.textStorage {
                        self.tocView.entries = TOCBuilder.build(from: storage)
                    }
                    self.applyThemeColors()
                    self.resolveDeferredAttachments()
                    self.notifyInitialRenderComplete()
                    self.finishLiveReload()
                    self.scheduleActiveHeadingUpdate()
                }
            } else {
                // Tier 2+: progressive render — first screenful fast, then complete
                pipeline.renderProgressive(
                    markdown: content,
                    theme: theme,
                    onFirstScreen: { [weak self] result in
                        guard let self = self else { return }
                        self.textView.textStorage?.setAttributedString(result.attributedString)
                        // Populate TOC from the first-screen render too —
                        // for large docs that take a while to fully render,
                        // this lets the sidebar show headings from the
                        // visible portion immediately. onComplete will
                        // replace with the full TOC once the rest renders.
                        if let storage = self.textView.textStorage {
                            self.tocView.entries = TOCBuilder.build(from: storage)
                        }
                        self.applyThemeColors()
                        self.notifyInitialRenderComplete()
                    },
                    onComplete: { [weak self] result in
                        guard let self = self else { return }
                        let scrollPosition = self.scrollView.contentView.bounds.origin
                        self.textView.textStorage?.setAttributedString(result.attributedString)
                        if let storage = self.textView.textStorage {
                            self.tocView.entries = TOCBuilder.build(from: storage)
                        }
                        self.scrollView.contentView.scroll(to: scrollPosition)
                        self.resolveDeferredAttachments()
                        MemoryMonitor.shared.checkAndLog()
                        self.finishLiveReload()
                        self.scheduleActiveHeadingUpdate()
                    }
                )
            }

        case .error(let message):
            pendingReadingAnchor = nil
            pendingFindMatch = nil
            showError(message)
        }
    }

    private func notifyInitialRenderComplete() {
        guard !didCompleteInitialRender else { return }
        didCompleteInitialRender = true
        // Decoupled from AppDelegate so this controller compiles into the
        // QL extension too (the extension has no AppDelegate). The main
        // app's AppDelegate observes this notification and ends its
        // launch-timing signpost.
        NotificationCenter.default.post(name: .markdownInitialRenderComplete, object: self)
    }

    private func showError(_ message: String) {
        let theme = ThemeManager.shared.currentTheme
        let attributed = NSAttributedString(
            string: message,
            attributes: [
                .font: theme.bodyFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        textView.textStorage?.setAttributedString(attributed)
        applyThemeColors()
    }

    // MARK: - Keyboard Navigation

    private func setupKeyViewLoop() {
        guard let openWithButton else { return }
        textView.nextKeyView = openWithButton
        openWithButton.nextKeyView = textView
    }

    // MARK: - Accessibility

    private func setupAccessibilityRotors() {
        let headingRotor = NSAccessibilityCustomRotor(label: "Headings", itemSearchDelegate: self)
        textView.setAccessibilityCustomRotors([headingRotor])
    }

    // MARK: - Active Heading Sync

    private func setupActiveHeadingSync() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleActiveHeadingUpdate()
        }
    }

    private func scheduleActiveHeadingUpdate() {
        activeHeadingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.updateActiveHeading()
        }
        activeHeadingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func updateActiveHeading() {
        let entries = tocView?.entries ?? []
        guard !entries.isEmpty,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            tocView?.activeEntry = nil
            return
        }
        let viewportTop = scrollView.contentView.bounds.origin.y
        let viewportHeight = scrollView.contentView.bounds.height
        let inset = textView.textContainerInset.height

        // Trigger normally sits 25% from the viewport top — matches the
        // 20% landing target in scrollToHeading so a clicked entry stays
        // highlighted. As we approach the doc bottom, the trigger slides
        // smoothly down toward the viewport bottom: short trailing
        // sections can't be pulled past a fixed top-anchored line, so
        // without this slide they never activate. Linear interpolation
        // over the last viewport-height of remaining scroll keeps the
        // transition continuous — no jumps when scrolling away from
        // the absolute bottom.
        let maxScrollY = max(0, textView.frame.height - viewportHeight)
        let remaining = max(0, maxScrollY - viewportTop)
        let zoneProgress = max(0.0, min(1.0, 1.0 - remaining / max(1, viewportHeight)))
        let standardOffset = viewportHeight * Self.activeHeadingBandFraction
        let triggerY = viewportTop + standardOffset + (viewportHeight - standardOffset) * zoneProgress

        var lastAbove: TOCEntry?
        for entry in entries {
            let range = NSRange(location: entry.location, length: 1)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let headingY = rect.origin.y + inset
            if headingY < triggerY {
                lastAbove = entry
            } else {
                break
            }
        }
        tocView?.activeEntry = lastAbove
    }

    // MARK: - Scroll Ahead

    private func setupScrollAhead() {
        scrollAheadController = ScrollAheadController(
            scrollView: scrollView,
            textLayoutManager: textView.textLayoutManager
        )
    }

    // MARK: - Deferred Attachments

    /// Fill in everything the renderer left as a placeholder — linked
    /// images, math, and Mermaid diagrams. One walk of the document, one
    /// provider per kind.
    private func resolveDeferredAttachments() {
        let generation = renderGeneration
        guard let textStorage = textView.textStorage else { return }
        let theme = ThemeManager.shared.currentTheme
        // Formulas are rasterised for this display, so a document dragged
        // to a non-Retina screen re-renders rather than being upscaled.
        let scale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2

        for (deferred, range) in DeferredAttachment.all(in: textStorage) {
            guard let attachment = textStorage.attribute(
                .attachment, at: range.location, effectiveRange: nil
            ) as? NSTextAttachment else { continue }

            switch deferred.kind {
            case .image:
                imageProvider.loadImage(from: deferred.source) { [weak self] image in
                    guard let self, let image else { return }
                    self.apply(generation: generation, range: range) {
                        attachment.bounds = NSRect(
                            origin: .zero,
                            size: self.constrainedImageSize(for: image)
                        )
                        attachment.image = image
                    }
                }

            case .inlineMath, .displayMath:
                mathProvider.image(
                    for: MathSpan(
                        latex: deferred.source,
                        isDisplay: deferred.kind == .displayMath
                    ),
                    fontSize: theme.bodyFontSize,
                    color: theme.textColor,
                    scale: scale
                ) { [weak self] rendered in
                    guard let self, let rendered else { return }
                    self.apply(generation: generation, range: range) {
                        attachment.bounds = rendered.layout.attachmentBounds
                        attachment.image = rendered.image
                    }
                }

            case .diagram:
                diagramProvider.image(
                    for: deferred.source,
                    theme: theme,
                    scale: scale
                ) { [weak self] image in
                    guard let self else { return }
                    guard let image else {
                        self.showDiagramSource(
                            generation: generation,
                            range: range,
                            source: deferred.source,
                            theme: theme
                        )
                        return
                    }
                    self.apply(generation: generation, range: range) {
                        attachment.bounds = NSRect(
                            origin: .zero,
                            size: self.constrainedImageSize(for: image)
                        )
                        attachment.image = image
                    }
                }
            }
        }
    }

    /// Put a diagram's own source back in the document, styled as a code
    /// block, because it could not be rendered.
    ///
    /// A malformed diagram must never read as a blank space, and the reader
    /// needs to see the text they wrote in order to fix it. This is the only
    /// place resolution changes the document's length rather than just an
    /// attachment's image, so it takes the same care a re-render does:
    /// the generation moves on, which drops every attachment request still in
    /// flight against the old offsets, and the walk starts again from the
    /// text as it now stands. Each pass replaces at most one diagram and the
    /// replacement carries no deferred attributes, so the loop always shrinks.
    private func showDiagramSource(
        generation: Int,
        range: NSRange,
        source: String,
        theme: Theme
    ) {
        guard renderGeneration == generation,
              let textStorage = textView.textStorage,
              NSMaxRange(range) <= textStorage.length else { return }

        let sourceBlockIndex = textStorage.attribute(
            .sourceBlockIndex, at: range.location, effectiveRange: nil
        ) as? Int

        textStorage.replaceCharacters(
            in: range,
            with: MarkdownRenderer.diagramFallback(
                source: source,
                theme: theme,
                sourceBlockIndex: sourceBlockIndex
            )
        )

        renderGeneration += 1
        scheduleDeferredAttachmentRescan()
    }

    /// Re-walk the document for deferred attachments once the current batch
    /// of callbacks has finished, coalescing several diagram replacements in
    /// the same batch into one pass.
    private func scheduleDeferredAttachmentRescan() {
        guard !isAttachmentRescanScheduled else { return }
        isAttachmentRescanScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isAttachmentRescanScheduled = false
            // The replacement moved every offset after it, so the headings
            // the TOC scrolls to have moved too.
            if let storage = self.textView.textStorage {
                self.tocView.entries = TOCBuilder.build(from: storage)
            }
            self.resolveDeferredAttachments()
        }
    }

    /// Commit a resolved attachment, unless the document moved on while it
    /// was being produced.
    private func apply(generation: Int, range: NSRange, _ change: () -> Void) {
        guard renderGeneration == generation,
              let textStorage = textView.textStorage,
              NSMaxRange(range) <= textStorage.length else { return }
        change()
        textStorage.beginEditing()
        textStorage.edited(.editedAttributes, range: range, changeInLength: 0)
        textStorage.endEditing()
    }

    private func constrainedImageSize(for image: NSImage) -> NSSize {
        let maxWidth: CGFloat
        if let containerWidth = textView.textContainer?.containerSize.width {
            let insets = textView.textContainerInset.width * 2
            maxWidth = containerWidth - insets
        } else {
            maxWidth = 600
        }

        let imageSize = image.size
        guard imageSize.width > maxWidth else { return imageSize }

        let scale = maxWidth / imageSize.width
        return NSSize(width: maxWidth, height: imageSize.height * scale)
    }

    // MARK: - TOC Navigation

    /// Exposes the current TOC entries so that TextInteractionHandler can
    /// resolve in-document fragment links without holding a strong reference
    /// to the tocView directly.
    var tocEntries: [TOCEntry] {
        tocView?.entries ?? []
    }

    func scrollToHeading(_ entry: TOCEntry) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let range = NSRange(location: entry.location, length: 1)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        layoutManager.ensureLayout(forCharacterRange: range)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let inset = textView.textContainerInset
        let viewportHeight = scrollView.contentView.bounds.height
        let targetY = rect.origin.y + inset.height - viewportHeight * 0.2
        let clampedY = max(0, targetY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - File Watching

    private func setupFileWatcher() {
        guard let fileURL else { return }
        let watcher = FileWatcher(url: fileURL)
        watcher.delegate = self
        watcher.start()
        self.fileWatcher = watcher
    }

    private func hideReloadBanner() {
        guard reloadBanner != nil else { return }
        reloadBanner?.removeFromSuperview()
        reloadBanner = nil

        // Restore scroll view to full size
        scrollView.frame = view.bounds
    }

    // MARK: - Live Reload

    /// Re-read and re-render the file, keeping the reader where they were.
    /// Called from the debouncer, so a burst of writes produces one render.
    private func performLiveReload() {
        guard fileURL != nil else { return }

        // A find match is the search's selection, not the reader's: it is
        // re-found in the new text below, so it must not hold the document
        // still. Incremental searching re-selects on every keystroke, so a
        // visible find bar owns the selection whoever set it.
        let findOwnsSelection = selectionBelongsToFind || findController.isFindBarVisible

        // Any other selection is the user's work in progress; replacing the
        // text storage would wipe it. Hold the reload until they let go.
        guard textView.selectedRange().length == 0 || findOwnsSelection else {
            isLiveReloadHeldBySelection = true
            return
        }

        isLiveReloadHeldBySelection = false
        pendingReadingAnchor = currentReadingAnchor()
        pendingFindMatch = findOwnsSelection ? findController.currentMatch() : nil
        gutterView.clear()
        loadMarkdownFile()
    }

    /// Called by `TextInteractionHandler` whenever the selection changes.
    func selectionDidChange(isEmpty: Bool) {
        // Assume the reader made this selection. `performFindAction` claims
        // it back afterwards for the find actions it drives, so only
        // selections find did not make hold a reload.
        selectionBelongsToFind = false
        guard isEmpty, isLiveReloadHeldBySelection else { return }
        performLiveReload()
    }

    /// Where the reader currently is, expressed as a heading plus an offset
    /// so it survives the document above them changing length.
    func currentReadingAnchor() -> ScrollAnchor {
        let viewportTop = scrollView.contentView.bounds.origin.y
        let viewportHeight = scrollView.contentView.bounds.height
        return ScrollAnchoring.anchor(
            headings: headingPositions(),
            viewportTop: viewportTop,
            band: viewportHeight * Self.activeHeadingBandFraction,
            maxScroll: max(0, textView.frame.height - viewportHeight)
        )
    }

    /// Restore the reading position and mark what changed. A no-op unless the
    /// render that just landed came from a live reload.
    private func finishLiveReload() {
        guard let anchor = pendingReadingAnchor else { return }
        pendingReadingAnchor = nil
        restoreReadingPosition(anchor)
        restorePendingFindMatch()
        flashChangedBlocks()
    }

    /// Re-find the match an active search was on. Runs after the reading
    /// position has been restored, so a match still on screen leaves the
    /// view where it was and only one that moved out of sight pulls it.
    private func restorePendingFindMatch() {
        guard let match = pendingFindMatch else { return }
        pendingFindMatch = nil
        findController.restore(match)
        // Selecting it went through the delegate, which assumes the reader
        // did it. It was the search.
        selectionBelongsToFind = true
    }

    private func restoreReadingPosition(_ anchor: ScrollAnchor) {
        let viewportHeight = scrollView.contentView.bounds.height
        let offset = ScrollAnchoring.offset(
            restoring: anchor,
            headingY: anchor.heading.flatMap(headingY(for:)),
            maxScroll: max(0, textView.frame.height - viewportHeight)
        )
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Lay out from the top of the document through `location`.
    ///
    /// Non-contiguous layout is on, so the geometry of a region that has not
    /// been laid out yet is an estimate extrapolated from the text above it —
    /// and a live reload changes exactly that text. Measuring straight after
    /// a re-render therefore has to force the layout it depends on, or the
    /// reading position and the accents both land in the wrong place. The
    /// work is bounded by how far down the document the caller is looking.
    private func ensureLayout(through location: Int) {
        textView.layoutManager?.ensureLayout(
            forCharacterRange: NSRange(location: 0, length: location)
        )
    }

    private func headingPositions() -> [HeadingPosition] {
        let entries = tocEntries
        guard !entries.isEmpty,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return [] }
        let inset = textView.textContainerInset.height
        return zip(entries, ScrollAnchoring.keys(for: entries)).map { entry, key in
            let range = NSRange(location: entry.location, length: 1)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            return HeadingPosition(key: key, y: rect.origin.y + inset)
        }
    }

    private func headingY(for key: HeadingKey) -> CGFloat? {
        let entries = tocEntries
        guard let index = ScrollAnchoring.keys(for: entries).firstIndex(of: key),
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return nil }
        let range = NSRange(location: entries[index].location, length: 1)
        ensureLayout(through: NSMaxRange(range))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        return rect.origin.y + textView.textContainerInset.height
    }

    private func flashChangedBlocks() {
        guard let textStorage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let newBlocks = BlockSplitter.split(markdownContent)
        let changed = Set(BlockDiff.changedIndices(
            from: BlockSplitter.split(previousMarkdownContent),
            to: newBlocks
        ))
        // Nothing changed, or everything did. A document-wide accent says
        // nothing about what the agent actually touched.
        guard !changed.isEmpty, changed.count < newBlocks.count else { return }

        var rendered: [BlockDiff.RenderedBlock] = []
        textStorage.enumerateAttribute(
            .sourceBlockIndex,
            in: NSRange(location: 0, length: textStorage.length),
            options: []
        ) { value, range, _ in
            guard let sourceIndex = value as? Int else { return }
            rendered.append(BlockDiff.RenderedBlock(sourceIndex: sourceIndex, range: range))
        }

        let ranges = BlockDiff.highlightRanges(
            changed: changed,
            rendered: rendered,
            sourceBlockCount: newBlocks.count
        )
        guard let lastRange = ranges.last else { return }
        ensureLayout(through: NSMaxRange(lastRange))

        let inset = textView.textContainerInset
        let bars = ranges.map { range -> NSRect in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.y += inset.height
            return ChangedBlockGutterView.bar(besideTextRect: rect, textLeftEdge: inset.width)
        }

        // Tall enough for every bar: the text view's own height can still be
        // catching up with the freshly laid-out document.
        let requiredHeight = bars.reduce(textView.bounds.height) { max($0, $1.maxY) }
        gutterView.frame = NSRect(
            x: 0, y: 0,
            width: textView.bounds.width,
            height: requiredHeight
        )
        gutterView.flash(bars, color: ThemeManager.shared.currentTheme.accentColor)
    }

    // MARK: - Find Actions

    @IBAction func showFindBar(_ sender: Any?) {
        performFindAction(.showFindInterface)
    }

    @IBAction func findNext(_ sender: Any?) {
        performFindAction(.nextMatch)
    }

    @IBAction func findPrevious(_ sender: Any?) {
        performFindAction(.previousMatch)
    }

    @IBAction func useSelectionForFind(_ sender: Any?) {
        performFindAction(.setSearchString)
    }

    private func performFindAction(_ action: NSTextFinder.Action) {
        findController.perform(action)
        // The action has just moved the selection, and the delegate
        // callback it fired on the way assumed the reader did it.
        selectionBelongsToFind = true
        // The bar may only now have been created, and it inherits the
        // window's appearance until it is told the document's.
        findController.applyTheme(ThemeManager.shared.currentTheme)
    }

    private func applyFindKeyEquivalentHandling() {
        guard isViewLoaded, let container = view as? MarkdownContainerView else { return }
        container.findAction = handlesFindKeyEquivalents
            ? { [weak self] action in self?.performFindAction(action) }
            : nil
    }

    // MARK: - Font Size Actions

    @IBAction func increaseFontSize(_ sender: Any?) {
        FontSizeManager.shared.increaseFontSize()
    }

    @IBAction func decreaseFontSize(_ sender: Any?) {
        FontSizeManager.shared.decreaseFontSize()
    }

    @IBAction func resetFontSize(_ sender: Any?) {
        FontSizeManager.shared.resetFontSize()
    }
}

// MARK: - Container View

/// The controller's root view.
///
/// In the app, find is driven from the Edit menu and this does nothing —
/// `findAction` stays nil, the shortcut falls through, and the menu item
/// highlights as it should. The Quick Look preview extension shares this
/// controller but has no menu bar, so it sets `findAction` and the
/// shortcuts are handled here instead.
final class MarkdownContainerView: NSView {

    var findAction: ((NSTextFinder.Action) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let findAction,
           let action = FindKeyEquivalent.action(
               characters: event.charactersIgnoringModifiers ?? "",
               modifiers: event.modifierFlags
           ) {
            findAction(action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - FileWatcherDelegate

extension MarkdownViewController: FileWatcherDelegate {

    func fileWatcher(_ watcher: FileWatcher, didDetectChangeFor url: URL) {
        // The file is readable again, so a deletion notice left over from a
        // rename is stale.
        hideReloadBanner()
        reloadDebouncer.schedule()
    }

    func fileWatcher(_ watcher: FileWatcher, didDetectDeletionOf url: URL) {
        guard reloadBanner == nil else { return }

        let banner = ReloadBannerView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.showDeletionMessage(path: url.lastPathComponent)
        banner.onDismiss = { [weak self] in
            self?.hideReloadBanner()
        }

        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        self.reloadBanner = banner

        // Adjust scroll view to account for banner
        scrollView.frame = NSRect(
            x: view.bounds.minX,
            y: view.bounds.minY,
            width: view.bounds.width,
            height: view.bounds.height - 32
        )
    }
}

// MARK: - NSAccessibilityCustomRotorItemSearchDelegate

extension MarkdownViewController: NSAccessibilityCustomRotorItemSearchDelegate {

    func rotor(
        _ rotor: NSAccessibilityCustomRotor,
        resultFor searchParameters: NSAccessibilityCustomRotor.SearchParameters
    ) -> NSAccessibilityCustomRotor.ItemResult? {
        guard let textStorage = textView.textStorage else { return nil }
        let length = textStorage.length
        guard length > 0 else { return nil }

        let currentIndex = searchParameters.currentItem?.targetRange.location ?? 0
        let forward = searchParameters.searchDirection == .next

        var found: NSRange?

        if forward {
            let searchStart = min(currentIndex + 1, length)
            let searchRange = NSRange(location: searchStart, length: length - searchStart)
            guard searchRange.length > 0 else { return nil }
            textStorage.enumerateAttribute(.accessibilityHeadingLevel, in: searchRange, options: []) { value, range, stop in
                if value != nil {
                    found = range
                    stop.pointee = true
                }
            }
        } else {
            let searchEnd = max(currentIndex, 0)
            let searchRange = NSRange(location: 0, length: searchEnd)
            guard searchRange.length > 0 else { return nil }
            textStorage.enumerateAttribute(.accessibilityHeadingLevel, in: searchRange, options: .reverse) { value, range, stop in
                if value != nil {
                    found = range
                    stop.pointee = true
                }
            }
        }

        guard let headingRange = found else { return nil }
        let item = NSAccessibilityCustomRotor.ItemResult(targetElement: textView)
        item.targetRange = headingRange
        item.customLabel = textStorage.attributedSubstring(from: headingRange).string
        return item
    }
}

// MARK: - Inline Code Border Drawing

/// Layout manager that draws 1px rounded borders for inline code spans
/// instead of filled background rectangles.
final class CodeBorderLayoutManager: NSLayoutManager {

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.inlineCodeBorderColor, in: charRange, options: []) { value, range, _ in
            guard let borderColor = value as? NSColor else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard let textContainer = self.textContainers.first else { return }

            self.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                var drawRect = rect
                drawRect.origin.x += origin.x
                drawRect.origin.y += origin.y
                // 3pt inner padding so the border doesn't crowd the glyphs.
                // Outer margin is handled by thin-space characters in the attributed string.
                drawRect = drawRect.insetBy(dx: -3, dy: 1.5)

                let path = NSBezierPath(roundedRect: drawRect, xRadius: 2, yRadius: 2)
                path.lineWidth = 1
                borderColor.setStroke()
                path.stroke()
            }
        }
    }
}

extension Notification.Name {
    /// Fired by MarkdownViewController on first complete render. The main
    /// app's AppDelegate observes this to end its launch-timing signpost.
    /// The QL extension doesn't observe (no launch signpost there).
    static let markdownInitialRenderComplete = Notification.Name("MarkdownInitialRenderComplete")
}
