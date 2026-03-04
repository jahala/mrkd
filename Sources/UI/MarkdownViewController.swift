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
    private var renderGeneration = 0

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
        pipeline.cancel()
        fileWatcher?.stop()
    }

    override func loadView() {
        let containerView = NSView()
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
        textContainer.widthTracksTextView = true
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

        scrollView.documentView = textView
        scrollView.frame = containerView.bounds
        containerView.addSubview(scrollView)

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

        self.view = containerView
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
    }

    private func rerender() {
        guard !markdownContent.isEmpty else { return }
        renderGeneration += 1
        let scrollPosition = scrollView.contentView.bounds.origin
        let theme = ThemeManager.shared.currentTheme

        pipeline.render(markdown: markdownContent, theme: theme) { [weak self] result in
            guard let self = self else { return }
            self.textView.textStorage?.setAttributedString(result.attributedString)
            self.applyThemeColors()
            self.loadDeferredImages()
            // Restore scroll position
            self.scrollView.contentView.scroll(to: scrollPosition)
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
            self.loadDeferredImages()
            self.notifyInitialRenderComplete()
        }
    }

    private func loadMarkdownFile() {
        guard let fileURL else { return }
        renderGeneration += 1
        let readResult = FileReader.read(url: fileURL)

        switch readResult {
        case .content(let content):
            markdownContent = content
            let theme = ThemeManager.shared.currentTheme
            let tier = FileTierRouter.tier(for: fileURL)

            if tier == .small {
                // Tier 1: full immediate render
                pipeline.render(markdown: content, theme: theme) { [weak self] result in
                    guard let self = self else { return }
                    self.textView.textStorage?.setAttributedString(result.attributedString)
                    self.applyThemeColors()
                    self.loadDeferredImages()
                    self.notifyInitialRenderComplete()
                }
            } else {
                // Tier 2+: progressive render — first screenful fast, then complete
                pipeline.renderProgressive(
                    markdown: content,
                    theme: theme,
                    onFirstScreen: { [weak self] result in
                        guard let self = self else { return }
                        self.textView.textStorage?.setAttributedString(result.attributedString)
                        self.applyThemeColors()
                        self.notifyInitialRenderComplete()
                    },
                    onComplete: { [weak self] result in
                        guard let self = self else { return }
                        let scrollPosition = self.scrollView.contentView.bounds.origin
                        self.textView.textStorage?.setAttributedString(result.attributedString)
                        self.scrollView.contentView.scroll(to: scrollPosition)
                        self.loadDeferredImages()
                        MemoryMonitor.shared.checkAndLog()
                    }
                )
            }

        case .error(let message):
            showError(message)
        }
    }

    private func notifyInitialRenderComplete() {
        guard !didCompleteInitialRender else { return }
        didCompleteInitialRender = true

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.notifyFirstRenderComplete()
        }
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

    // MARK: - Scroll Ahead

    private func setupScrollAhead() {
        scrollAheadController = ScrollAheadController(
            scrollView: scrollView,
            textLayoutManager: textView.textLayoutManager
        )
    }

    // MARK: - Deferred Image Loading

    private func loadDeferredImages() {
        let generation = renderGeneration
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.enumerateAttribute(.imageSourceURL, in: fullRange, options: []) { [weak self] value, range, _ in
            guard let self, let urlString = value as? String else { return }
            guard let attachment = textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment else { return }

            self.imageProvider.loadImage(from: urlString) { [weak self] image in
                guard let self, self.renderGeneration == generation else { return }
                guard let image else { return }
                guard let textStorage = self.textView.textStorage else { return }

                // Verify range is still valid in current storage
                guard range.location + range.length <= textStorage.length else { return }

                let constrainedSize = self.constrainedImageSize(for: image)
                attachment.bounds = NSRect(origin: .zero, size: constrainedSize)
                attachment.image = image

                textStorage.beginEditing()
                textStorage.edited(.editedAttributes, range: range, changeInLength: 0)
                textStorage.endEditing()
            }
        }
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

    // MARK: - File Watching

    private func setupFileWatcher() {
        guard let fileURL else { return }
        let watcher = FileWatcher(url: fileURL)
        watcher.delegate = self
        watcher.start()
        self.fileWatcher = watcher
    }

    private func showReloadBanner() {
        // Don't show banner twice
        if reloadBanner != nil {
            return
        }

        let banner = ReloadBannerView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.onReload = { [weak self] in
            self?.reloadFile()
        }
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

    private func hideReloadBanner() {
        reloadBanner?.removeFromSuperview()
        reloadBanner = nil

        // Restore scroll view to full size
        scrollView.frame = view.bounds
    }

    private func reloadFile() {
        hideReloadBanner()
        loadMarkdownFile()
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

// MARK: - FileWatcherDelegate

extension MarkdownViewController: FileWatcherDelegate {

    func fileWatcher(_ watcher: FileWatcher, didDetectChangeFor url: URL) {
        showReloadBanner()
    }

    func fileWatcher(_ watcher: FileWatcher, didDetectDeletionOf url: URL) {
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
