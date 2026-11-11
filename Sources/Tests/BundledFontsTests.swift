import XCTest
@testable import mrkd

/// The list of font files mrkd ships. Both CoreText and the Mermaid
/// renderer read it, and a diagram in a different typeface from the prose
/// around it is what a disagreement between them looks like.
final class BundledFontsTests: XCTestCase {

    func testEveryShippedTypefaceIsFound() {
        let found = BundledFonts.fontFiles(in: Self.repositoryFontDirectory)
        let names = found.map(\.lastPathComponent)

        // The families the settings window offers as body fonts. If one of
        // these stops being found, choosing it leaves the diagram in a
        // system fallback while the document changes face.
        for expected in [
            "Inter-Variable.ttf", "Literata-Variable.ttf", "Geist-Variable.ttf",
            "OpenSans-Variable.ttf", "SourceSans3-Variable.ttf", "Merriweather-Variable.ttf",
            "JetBrainsMono-Variable.ttf", "SourceCodePro-Variable.ttf", "iAWriterMonoV.ttf",
        ] {
            XCTAssertTrue(names.contains(expected), "\(expected) is not in the bundled fonts")
        }
    }

    /// Everything in the real directory is a font, so the filter is tested
    /// against one that also holds the sort of file a resources directory
    /// picks up. A licence file handed to the renderer as a font is a failed
    /// render for every diagram in the document.
    func testNothingThatIsNotAFontIsPickedUp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mrkd-fonts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["Inter-Variable.ttf", "OFL.txt", "README.md", "notes"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }

        let found = BundledFonts.fontFiles(in: directory)

        XCTAssertEqual(found.map(\.lastPathComponent), ["Inter-Variable.ttf"])
    }

    /// Stable order, because the renderer caches its font database against
    /// this list: a different order every launch would rebuild it, and that
    /// costs a few hundred milliseconds on the first diagram.
    func testTheOrderIsStable() {
        let first = BundledFonts.fontFiles(in: Self.repositoryFontDirectory)
        let again = BundledFonts.fontFiles(in: Self.repositoryFontDirectory)

        XCTAssertEqual(first, again)
        XCTAssertEqual(first, first.sorted { $0.path < $1.path })
    }

    /// The Quick Look extension carries no fonts of its own. It must find the
    /// ones in the app it is embedded in, or every preview falls back to the
    /// system font for prose and diagrams alike (issue #18).
    func testAnExtensionFindsTheFontsOfTheAppItIsEmbeddedIn() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mrkd-bundle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("mrkd.app")
        let fonts = app.appendingPathComponent("Contents/Resources/Fonts")
        let appex = app.appendingPathComponent("Contents/PlugIns/QLPlugin.appex")
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: appex.appendingPathComponent("Contents/Resources"),
            withIntermediateDirectories: true
        )
        try Data().write(to: fonts.appendingPathComponent("Inter-Variable.ttf"))

        // Paths are compared resolved: the temporary folder sits behind the
        // /var -> /private/var link, and a directory listing reports the
        // other side of it.
        func resolved(_ urls: [URL]) -> [URL] { urls.map { $0.resolvingSymlinksInPath() } }
        let expected = resolved([fonts.appendingPathComponent("Inter-Variable.ttf")])
        XCTAssertEqual(resolved(BundledFonts.fontFiles(forBundleAt: app)), expected)
        XCTAssertEqual(resolved(BundledFonts.fontFiles(forBundleAt: appex)), expected)
    }

    func testADirectoryThatIsNotThereIsEmptyRatherThanFatal() {
        let missing = URL(fileURLWithPath: "/nonexistent/mrkd/Fonts")

        XCTAssertEqual(BundledFonts.fontFiles(in: missing), [])
    }
}

extension XCTestCase {

    /// The repository's own font directory.
    ///
    /// `Bundle.main` under `swift test` is the test runner, which carries no
    /// Resources/Fonts, so the tests read the very files the app bundle would
    /// carry instead of asserting against a bundle that does not exist.
    static var repositoryFontDirectory: URL {
        URL(fileURLWithPath: #filePath)          // Sources/Tests/BundledFontsTests.swift
            .deletingLastPathComponent()         // Sources/Tests
            .deletingLastPathComponent()         // Sources
            .appendingPathComponent("Resources/Fonts")
    }

    /// The font files the app would hand the Mermaid renderer.
    static var repositoryFontURLs: [URL] {
        BundledFonts.fontFiles(in: repositoryFontDirectory)
    }
}
