import XCTest
import AppKit
@testable import mrkd

/// The reading width setting, end to end: a real controller in a real
/// (offscreen) window, measured through its text container.
@MainActor
final class ReadingWidthTests: XCTestCase {

    private var windows: [NSWindow] = []
    private var savedReadingWidth: Any?
    private var savedDefaultsReadingWidth: Any?

    private static let appID = "com.mrkd.app" as CFString
    private static let key = "readingWidth"

    override func setUp() async throws {
        // Bring the shared application up before anything reads `NSApp`;
        // these tests can be the first thing to run in the process.
        _ = NSApplication.shared
        savedReadingWidth = CFPreferencesCopyAppValue(Self.key as CFString, Self.appID)
        savedDefaultsReadingWidth = UserDefaults.standard.object(forKey: Self.key)
    }

    override func tearDown() async throws {
        for window in windows { window.contentViewController = nil }
        windows.removeAll()
        CFPreferencesSetAppValue(Self.key as CFString, savedReadingWidth as CFPropertyList?, Self.appID)
        CFPreferencesAppSynchronize(Self.appID)
        UserDefaults.standard.set(savedDefaultsReadingWidth, forKey: Self.key)
    }

    // MARK: - Helpers

    private func storeReadingWidth(_ rawValue: String?) {
        CFPreferencesSetAppValue(Self.key as CFString, rawValue as CFPropertyList?, Self.appID)
        CFPreferencesAppSynchronize(Self.appID)
    }

    private func makeController(width: CGFloat) -> MarkdownViewController {
        host(MarkdownViewController(markdownString: "# Title\n\nSome body text."), width: width)
    }

    private func makeController(for document: URL, width: CGFloat) -> MarkdownViewController {
        host(MarkdownViewController(fileURL: document), width: width)
    }

    private func host(_ vc: MarkdownViewController, width: CGFloat) -> MarkdownViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.setContentSize(NSSize(width: width, height: 700))
        window.layoutIfNeeded()
        windows.append(window)
        return vc
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }

    private func columnWidth(of vc: MarkdownViewController) -> CGFloat? {
        textView(in: vc.view)?.textContainer?.containerSize.width
    }

    private func contentsSidebar(in view: NSView) -> TOCFloatingView? {
        if let toc = view as? TOCFloatingView { return toc }
        for subview in view.subviews {
            if let found = contentsSidebar(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Column follows the setting

    func testStoredWideSettingWidensTheColumn() throws {
        storeReadingWidth("wide")
        let vc = makeController(width: 1600)
        XCTAssertEqual(columnWidth(of: vc), 1040)
    }

    func testUnsetSettingKeepsTheOld800PointColumn() throws {
        storeReadingWidth(nil)
        XCTAssertEqual(ThemeManager.shared.readingWidth, .standard)
        let vc = makeController(width: 1600)
        XCTAssertEqual(columnWidth(of: vc), 800)
    }

    func testUnknownStoredValueReadsAsStandard() {
        storeReadingWidth("enormous")
        XCTAssertEqual(ThemeManager.shared.readingWidth, .standard)
    }

    func testEveryChoiceSetsItsOwnColumnInAWideWindow() throws {
        let expected: [ReadingWidth: CGFloat] = [
            .narrow: 640, .standard: 800, .wide: 1040, .fullWindow: 1600 - 120,
        ]
        for width in ReadingWidth.allCases {
            storeReadingWidth(width.rawValue)
            let vc = makeController(width: 1600)
            XCTAssertEqual(columnWidth(of: vc), expected[width], "\(width)")
            let inset = textView(in: vc.view)?.textContainerInset.width
            XCTAssertEqual(inset, max(60, (1600 - (expected[width] ?? 0)) / 2), "\(width)")
        }
    }

    func testChangingTheSettingResizesEveryOpenWindowAtOnce() throws {
        storeReadingWidth(nil)
        let first = makeController(width: 1600)
        let second = makeController(width: 1300)
        XCTAssertEqual(columnWidth(of: first), 800)
        XCTAssertEqual(columnWidth(of: second), 800)

        ThemeManager.shared.readingWidth = .fullWindow

        XCTAssertEqual(columnWidth(of: first), 1600 - 120)
        XCTAssertEqual(columnWidth(of: second), 1300 - 120)
        XCTAssertEqual(
            CFPreferencesCopyAppValue(Self.key as CFString, Self.appID) as? String,
            "fullWindow",
            "the Quick Look extension reads the setting from the app's preferences"
        )
    }

    // MARK: - Smallest window

    /// At the smallest window mrkd allows, every choice is wider than the
    /// room there is. The column then fills the window less the side
    /// padding, so the text never runs under the window edge.
    func testAtTheMinimumWindowEveryChoiceKeepsTheSidePadding() {
        for fontSize in [11, 13, 16, 20] as [CGFloat] {
            let theme = DefaultTheme(baseFontSize: fontSize, fontFamily: "SF Mono", codeFontFamily: "JetBrains Mono")
            let windowWidth = WindowSizer.minimumSize(for: theme).width
            for width in ReadingWidth.allCases {
                let layout = ColumnLayout(viewWidth: windowWidth, readingWidth: width)
                let limit = min(width.maxColumnWidth ?? .greatestFiniteMagnitude, windowWidth - 120)
                XCTAssertEqual(layout.columnWidth, limit, "\(width) at \(fontSize) pt")
                XCTAssertGreaterThan(layout.columnWidth, 0, "\(width) at \(fontSize) pt")
                XCTAssertGreaterThanOrEqual(layout.sideInset, 60, "\(width) at \(fontSize) pt")
                XCTAssertEqual(layout.columnWidth + 2 * layout.sideInset, windowWidth, accuracy: 0.001)
            }
        }
    }

    func testMinimumWindowColumnInTheController() throws {
        storeReadingWidth("narrow")
        let vc = makeController(width: WindowSizer.minimumSize(for: ThemeManager.shared.currentTheme).width)
        // The window rounds its size to whole points; measure what it chose.
        let viewWidth = vc.view.bounds.width
        let column = min(640, viewWidth - 120)
        XCTAssertEqual(columnWidth(of: vc), column)
        XCTAssertEqual(textView(in: vc.view)?.textContainerInset.width, max(60, (viewWidth - column) / 2))
    }

    // MARK: - Contents sidebar

    /// The sidebar has no background, so it shows only in the margin beside
    /// the column. At the standard width that is the old 1280-point rule.
    func testStandardWidthKeepsTheOldSidebarThreshold() throws {
        storeReadingWidth(nil)
        XCTAssertEqual(contentsSidebar(in: makeController(width: 1280).view)?.isHidden, false)
        XCTAssertEqual(contentsSidebar(in: makeController(width: 1279).view)?.isHidden, true)
    }

    func testSidebarNeverCoversAWiderColumn() throws {
        storeReadingWidth("wide")
        // 1040 + 2 × (200 sidebar + 24 margin + 16 gap) = 1520.
        XCTAssertEqual(contentsSidebar(in: makeController(width: 1520).view)?.isHidden, false)
        XCTAssertEqual(contentsSidebar(in: makeController(width: 1400).view)?.isHidden, true)

        storeReadingWidth("fullWindow")
        XCTAssertEqual(contentsSidebar(in: makeController(width: 2400).view)?.isHidden, true)
    }

    // MARK: - Images

    /// A document holding one picture far wider than any column, in a
    /// folder the caller removes.
    private func writeWideImageDocument() throws -> (folder: URL, document: URL) {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-reading-width-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 300,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: folder.appendingPathComponent("wide.png"))
        let document = folder.appendingPathComponent("doc.md")
        try "# Picture\n\n![wide](wide.png)\n".write(to: document, atomically: true, encoding: .utf8)
        return (folder, document)
    }

    /// The width of one line in the column: the container less its line
    /// fragment padding on each side.
    private func lineWidth(of vc: MarkdownViewController) -> CGFloat? {
        guard let container = textView(in: vc.view)?.textContainer else { return nil }
        return container.containerSize.width - 2 * container.lineFragmentPadding
    }

    /// Waits until the loaded picture is in place at `expected` width, and
    /// returns the width it settled at.
    private func imageWidth(in vc: MarkdownViewController, settlingAt expected: CGFloat?) -> CGFloat? {
        var width: CGFloat?
        let deadline = Date().addingTimeInterval(6)
        repeat {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            guard let storage = textView(in: vc.view)?.textStorage else { continue }
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                // The provider caps the 3000-pixel picture at 2048;
                // anything else is still the renderer's placeholder.
                if let attachment = value as? NSTextAttachment, attachment.image?.size.width == 2048 {
                    width = attachment.bounds.width
                }
            }
        } while width != expected && Date() < deadline
        return width
    }

    /// A picture wider than the column is scaled to fit the column, at
    /// every reading width. The side margins sit outside the column, so
    /// they must not shrink the picture again.
    func testWideImageFillsTheColumnAtEveryWidth() throws {
        let fixture = try writeWideImageDocument()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }

        for width in ReadingWidth.allCases {
            storeReadingWidth(width.rawValue)
            let vc = makeController(for: fixture.document, width: 1400)
            let expected = try XCTUnwrap(lineWidth(of: vc))
            XCTAssertEqual(imageWidth(in: vc, settlingAt: expected), expected, "\(width)")
        }
    }

    func testChangingTheSettingRefitsAnOpenPicture() throws {
        let fixture = try writeWideImageDocument()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        storeReadingWidth("narrow")
        let vc = makeController(for: fixture.document, width: 1400)
        XCTAssertEqual(imageWidth(in: vc, settlingAt: 630), 630)

        ThemeManager.shared.readingWidth = .wide

        XCTAssertEqual(imageWidth(in: vc, settlingAt: 1030), 1030)
    }

    func testNarrowWidthShowsTheSidebarInSmallerWindows() throws {
        storeReadingWidth("narrow")
        // 640 + 2 × 240 = 1120.
        XCTAssertEqual(contentsSidebar(in: makeController(width: 1120).view)?.isHidden, false)
    }
}
