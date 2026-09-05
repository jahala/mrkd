import XCTest
import AppKit
@testable import mrkd

/// Math in a live document: a real file on disk, a real controller in a
/// real (offscreen) window, real SwaTex bitmaps. This is where the feature
/// meets the three things that landed before it — live reload, find in
/// page, and the changed-block accents.
@MainActor
final class MathIntegrationTests: XCTestCase {

    private var tempDir: URL!
    private var windows: [NSWindow] = []
    private var savedFontSize: Any?
    private var savedFindString: String?
    private var savedTheme: String?
    private var savedAppAppearance: NSAppearance?

    private static let appID = "com.mrkd.app" as CFString

    override func setUp() async throws {
        _ = NSApplication.shared
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrkd-math-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        savedFontSize = CFPreferencesCopyAppValue("fontSize" as CFString, Self.appID)
        savedFindString = NSPasteboard(name: .find).string(forType: .string)
        savedTheme = CFPreferencesCopyAppValue("selectedTheme" as CFString, Self.appID) as? String
        savedAppAppearance = NSApp.appearance
    }

    override func tearDown() async throws {
        for window in windows { window.contentViewController = nil }
        windows.removeAll()
        CFPreferencesSetAppValue(
            "fontSize" as CFString,
            savedFontSize as CFPropertyList?,
            Self.appID
        )
        CFPreferencesSetAppValue(
            "selectedTheme" as CFString,
            savedTheme as CFPropertyList?,
            Self.appID
        )
        CFPreferencesAppSynchronize(Self.appID)
        UserDefaults.standard.removeObject(forKey: "fontSize")
        UserDefaults.standard.removeObject(forKey: "selectedTheme")
        NSApp.appearance = savedAppAppearance
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        if let savedFindString { pasteboard.setString(savedFindString, forType: .string) }
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func writeFixture(name: String, contents: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = 6, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func makeController(for url: URL) -> MarkdownViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let vc = MarkdownViewController(fileURL: url)
        window.contentViewController = vc
        window.setContentSize(NSSize(width: 1000, height: 800))
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

    /// The attachments the renderer left for math, in document order.
    private func mathAttachments(in textView: NSTextView) -> [NSTextAttachment] {
        guard let storage = textView.textStorage else { return [] }
        return DeferredAttachment.all(in: storage).compactMap { entry in
            guard entry.attachment.kind != .image else { return nil }
            return storage.attribute(
                .attachment, at: entry.range.location, effectiveRange: nil
            ) as? NSTextAttachment
        }
    }

    private func firstMathImage(in textView: NSTextView) -> NSImage? {
        mathAttachments(in: textView).first?.image
    }

    // MARK: - Tests

    func testFormulaInADocumentIsRasterisedIntoItsAttachment() throws {
        let url = try writeFixture(
            name: "math.md",
            contents: "# Physics\n\nEinstein wrote $E = mc^2$ on a board.\n"
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))

        XCTAssertTrue(
            waitUntil { self.firstMathImage(in: textView) != nil },
            "the formula never got its bitmap"
        )
        let image = try XCTUnwrap(firstMathImage(in: textView))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// The box the renderer reserved and the bitmap the view puts in it are
    /// measured by two different calls; if they disagree the formula is
    /// drawn stretched.
    func testResolvedFormulaBoxMatchesItsBitmap() throws {
        let url = try writeFixture(
            name: "box.md",
            contents: "# Box\n\nA formula $\\int_0^1 x\\,dx$ here.\n"
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { self.firstMathImage(in: textView) != nil })

        let attachment = try XCTUnwrap(mathAttachments(in: textView).first)
        let image = try XCTUnwrap(attachment.image)
        XCTAssertEqual(attachment.bounds.width, image.size.width, accuracy: 0.01)
        XCTAssertEqual(attachment.bounds.height, image.size.height, accuracy: 0.01)
    }

    /// The cache earns its keep here: an agent rewriting the file must not
    /// send every unchanged formula back through SwaTex.
    func testUnchangedFormulaIsReusedAcrossALiveReload() throws {
        let url = try writeFixture(
            name: "reload.md",
            contents: "# Before\n\nEinstein wrote $E = mc^2$ on a board.\n"
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { self.firstMathImage(in: textView) != nil })
        let before = try XCTUnwrap(firstMathImage(in: textView))

        try "# After\n\nEinstein wrote $E = mc^2$ on a board.\n"
            .write(to: url, atomically: false, encoding: .utf8)
        XCTAssertTrue(
            waitUntil { vc.tocEntries.first?.text == "After" },
            "live reload never landed"
        )

        XCTAssertTrue(
            waitUntil { self.firstMathImage(in: textView) != nil },
            "the formula lost its bitmap across the reload"
        )
        XCTAssertTrue(
            firstMathImage(in: textView) === before,
            "an unchanged formula must come back from the cache, not the renderer"
        )
    }

    /// Attachments are a single character each, so they shift every offset
    /// after them. Find has to still land on the right text.
    func testFindMatchesTextThatSitsAfterAFormula() throws {
        let url = try writeFixture(
            name: "find.md",
            contents: "# Doc\n\nBefore $x^2$ then the marmalade word.\n"
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { self.firstMathImage(in: textView) != nil })

        let range = (textView.string as NSString).range(of: "marmalade")
        XCTAssertNotEqual(range.location, NSNotFound, "fixture text missing")
        textView.setSelectedRange(range)
        vc.useSelectionForFind(nil)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        vc.findNext(nil)

        let selected = (textView.string as NSString).substring(with: textView.selectedRange())
        XCTAssertEqual(selected.lowercased(), "marmalade")
    }

    func testChangedBlockAccentStillPointsAtTheBlockAFormulaIsIn() throws {
        let url = try writeFixture(
            name: "accent.md",
            contents: "# Title\n\nPlain paragraph.\n\nA formula $x^2$ here.\n"
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { self.firstMathImage(in: textView) != nil })

        let storage = try XCTUnwrap(textView.textStorage)
        let entry = try XCTUnwrap(
            DeferredAttachment.all(in: storage).first { $0.attachment.kind != .image }
        )
        let blockIndex = storage.attribute(
            .sourceBlockIndex, at: entry.range.location, effectiveRange: nil
        ) as? Int
        XCTAssertEqual(blockIndex, 2, "the formula is in the third block of the file")
    }

    /// Average brightness of the drawn glyphs, ignoring the transparent
    /// ground the formula is rendered on.
    private func inkBrightness(of image: NSImage) -> Double? {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total = 0.0
        var counted = 0.0
        for pixel in 0..<(width * height) where bytes[pixel * 4 + 3] > 200 {
            // Premultiplied, but alpha is ~255 here, so the channels are the
            // glyph's own colour.
            total += (Double(bytes[pixel * 4])
                + Double(bytes[pixel * 4 + 1])
                + Double(bytes[pixel * 4 + 2])) / 3
            counted += 1
        }
        guard counted > 0 else { return nil }
        return total / counted / 255
    }

    /// A formula is drawn once, into a bitmap, so its colour is baked in —
    /// it cannot inherit the theme the way text does. On a dark theme it
    /// has to come out light, or the document has a black formula on a
    /// black background.
    func testFormulaIsDrawnInTheDarkThemesBodyColour() throws {
        ThemeManager.shared.selectedThemeName = "Catppuccin Mocha"
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let theme = ThemeManager.shared.currentTheme
        try XCTSkipUnless(theme.isDark, "expected a dark theme to be active")

        let url = try writeFixture(
            name: "dark.md",
            contents: "# Dark\n\nA formula $E = mc^2$ here.\n"
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { self.firstMathImage(in: textView) != nil })

        let brightness = try XCTUnwrap(inkBrightness(of: try XCTUnwrap(firstMathImage(in: textView))))
        XCTAssertGreaterThan(
            brightness, 0.5,
            "the formula is dark ink on a dark page — the theme colour was not used"
        )
    }

    /// Cmd-+ changes the theme's body size, and the formula has to grow
    /// with the text around it rather than staying at the old size.
    func testZoomRerendersTheFormulaLarger() throws {
        ThemeManager.shared.fontSize = 13
        let url = try writeFixture(
            name: "zoom.md",
            contents: "# Zoom\n\nA formula $E = mc^2$ here.\n"
        )
        let vc = makeController(for: url)
        let textView = try XCTUnwrap(self.textView(in: vc.view))
        XCTAssertTrue(waitUntil { self.firstMathImage(in: textView) != nil })
        let smallWidth = try XCTUnwrap(firstMathImage(in: textView)).size.width

        ThemeManager.shared.fontSize = 26
        XCTAssertTrue(
            waitUntil {
                guard let image = self.firstMathImage(in: textView) else { return false }
                return image.size.width > smallWidth * 1.5
            },
            "the formula did not follow the zoom (stayed at \(smallWidth)pt wide)"
        )
    }
}
