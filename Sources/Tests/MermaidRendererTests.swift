import XCTest
import AppKit
import CMermaid
@testable import mrkd

/// Real diagrams through the real merman library in
/// `Frameworks/libmermaid_shim.dylib`. Nothing here is stubbed: if the dylib
/// is missing these do not fail, they fail to link, which is the point.
final class MermaidRendererTests: XCTestCase {

    private let flowchart = """
        flowchart TD
          A[Read the file] --> B{Is it markdown?}
          B -->|yes| C[Render]
          B -->|no| D[Open elsewhere]
        """

    private let sequence = """
        sequenceDiagram
          participant U as User
          participant M as mrkd
          U->>M: open plan.md
          M-->>U: rendered document
        """

    private func dark() -> String { MermaidThemePayload.json(for: CatppuccinMochaTheme()) }
    private func light() -> String { MermaidThemePayload.json(for: GitHubLight()) }

    private func render(
        _ source: String,
        theme: String? = nil,
        fonts: [URL]? = nil,
        scale: CGFloat = 2
    ) -> Result<NSImage, MermaidRenderFailure> {
        MermaidRenderer.image(
            source: source,
            themeJSON: theme ?? dark(),
            fontURLs: fonts ?? Self.repositoryFontURLs,
            scale: scale
        )
    }

    /// The dark theme in a chosen body font, as the payload the app builds.
    private func theme(font: String) -> String {
        MermaidThemePayload.json(for: CatppuccinMochaTheme(fontFamily: font))
    }

    /// The PNG bytes of a rendered diagram, for comparing two renders.
    private func pixels(_ image: NSImage) throws -> Data {
        try XCTUnwrap(
            (image.representations.first as? NSBitmapImageRep)?
                .representation(using: .png, properties: [:])
        )
    }

    // MARK: - Real diagrams

    func testAFlowchartRendersToABitmapBigEnoughToBeTheDiagram() throws {
        let image = try render(flowchart).get()

        // Four labelled nodes and three edges cannot fit in a small box; this
        // catches a renderer that returns a blank or degenerate image.
        XCTAssertGreaterThan(image.size.width, 100)
        XCTAssertGreaterThan(image.size.height, 100)
        XCTAssertFalse(image.representations.isEmpty)
    }

    func testASequenceDiagramRenders() throws {
        let image = try render(sequence).get()

        XCTAssertGreaterThan(image.size.width, 100)
        XCTAssertGreaterThan(image.size.height, 100)
    }

    func testTheBitmapIsRasterisedAtTheRequestedScaleButMeasuredInPoints() throws {
        let atOne = try render(flowchart, scale: 1).get()
        let atTwo = try render(flowchart, scale: 2).get()

        // Same size on the page…
        XCTAssertEqual(atOne.size.width, atTwo.size.width, accuracy: 1)
        XCTAssertEqual(atOne.size.height, atTwo.size.height, accuracy: 1)

        // …twice the pixels in it. Getting this wrong is how a Retina diagram
        // ends up drawn at double size or blurred at half resolution.
        let onePixels = try XCTUnwrap(atOne.representations.first).pixelsWide
        let twoPixels = try XCTUnwrap(atTwo.representations.first).pixelsWide
        XCTAssertEqual(twoPixels, onePixels * 2, accuracy: 2)
    }

    func testTheThemeReachesThePixels() throws {
        let inDark = try render(flowchart, theme: dark()).get()
        let inLight = try render(flowchart, theme: light()).get()

        XCTAssertNotEqual(
            try pixels(inDark), try pixels(inLight),
            "the theme never reached the renderer"
        )
    }

    // MARK: - Fonts

    /// A diagram is part of the prose, so it has to be set in the same face.
    /// The document's body font is the only thing that differs between these
    /// two renders, and the pixels have to differ with it.
    ///
    /// Two families mrkd ships and the system does not, so that a machine
    /// with one of them separately installed cannot make this pass for the
    /// wrong reason: without the bundled files both fall back to the same
    /// system sans and the bytes match.
    func testTheDocumentsBodyFontChangesTheGlyphs() throws {
        let inInter = try render(flowchart, theme: theme(font: "Inter")).get()
        let inGeist = try render(flowchart, theme: theme(font: "Geist")).get()

        XCTAssertEqual(
            inInter.size.width, inGeist.size.width, accuracy: 1,
            "the two renders are different sizes, so this compares more than the glyphs"
        )
        XCTAssertNotEqual(
            try pixels(inInter), try pixels(inGeist),
            "Inter and Geist drew the same pixels — the theme's font never reached the glyphs"
        )
    }

    /// The same theme, rendered with and without mrkd's own font files.
    /// Without them Inter — the app's own body font — is not a face the
    /// rasteriser has ever heard of, and it draws a system sans instead.
    func testWithoutTheBundledFilesTheBodyFontCannotBeUsed() throws {
        let withFonts = try render(flowchart, theme: theme(font: "Inter")).get()
        let withoutFonts = try render(flowchart, theme: theme(font: "Inter"), fonts: []).get()

        XCTAssertNotEqual(
            try pixels(withFonts), try pixels(withoutFonts),
            "handing the renderer mrkd's fonts made no difference to the pixels"
        )
    }

    /// A file in the list that is not a font is a broken build, and it says
    /// so rather than quietly drawing every diagram in a fallback face.
    func testAFileThatIsNotAFontIsReported() {
        let notAFont = URL(fileURLWithPath: #filePath)

        XCTAssertEqual(
            render(flowchart, fonts: [notAFont]).failureValue, .fontLoadFailed
        )
    }

    /// The diagram sits on the document, not on a card. An opaque background
    /// is the white-rectangle-in-a-dark-theme bug, and it is invisible to
    /// every assertion about size.
    func testTheDiagramBackgroundIsTransparent() throws {
        let image = try render(flowchart, scale: 1).get()
        let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)

        let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0))
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.01,
                       "the diagram is painted on an opaque card")
    }

    /// A dark theme has to produce dark ink somewhere in the picture. Byte
    /// inequality alone would pass even if both themes rendered white.
    func testADarkThemeProducesADarkDiagram() throws {
        let image = try render(flowchart, theme: dark(), scale: 1).get()
        let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)

        var darkOpaquePixels = 0
        var opaquePixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.9 else {
                    continue
                }
                opaquePixels += 1
                if pixel.brightnessComponent < 0.35 { darkOpaquePixels += 1 }
            }
        }

        XCTAssertGreaterThan(opaquePixels, 0, "nothing was drawn at all")
        XCTAssertGreaterThan(
            Double(darkOpaquePixels) / Double(opaquePixels), 0.5,
            "a dark theme drew a mostly light diagram"
        )
    }

    // MARK: - Failure

    func testAMalformedDiagramFailsRatherThanRenderingSomething() {
        switch render("flowchart TD\n  A[Unclosed --> B{{{") {
        case .success(let image):
            XCTFail("a broken diagram produced a \(image.size) bitmap")
        case .failure(let failure):
            XCTAssertEqual(failure, .renderFailed)
        }
    }

    func testProseIsNotADiagram() {
        switch render("this is just some prose, not a diagram") {
        case .success: XCTFail("prose rendered as a diagram")
        case .failure(let failure): XCTAssertEqual(failure, .renderFailed)
        }
    }

    func testAnEmptySourceIsRejectedWithoutCallingTheRenderer() {
        XCTAssertEqual(render("").failureValue, .invalidInput)
    }

    func testAnEmptyThemeIsRejected() {
        // An empty payload means MermaidThemePayload could not encode the
        // theme. Rendering anyway would silently produce an un-themed diagram.
        XCTAssertEqual(render(flowchart, theme: "").failureValue, .invalidInput)
    }

    func testAThemeThatIsNotJSONIsRejected() {
        XCTAssertEqual(render(flowchart, theme: "{not json").failureValue, .invalidInput)
    }

    func testANonPositiveOrNonFiniteScaleIsRejected() {
        for scale in [CGFloat(0), -1, .nan, .infinity] {
            XCTAssertEqual(
                render(flowchart, scale: scale).failureValue, .invalidInput,
                "scale \(scale) should have been rejected"
            )
        }
    }

    func testStatusCodesMapToTheirFailures() {
        XCTAssertEqual(MermaidRenderFailure(status: MERMAID_ERR_INVALID_INPUT), .invalidInput)
        XCTAssertEqual(MermaidRenderFailure(status: MERMAID_ERR_NO_DIAGRAM), .noDiagram)
        XCTAssertEqual(MermaidRenderFailure(status: MERMAID_ERR_RENDER), .renderFailed)
        XCTAssertEqual(MermaidRenderFailure(status: MERMAID_ERR_PANIC), .rendererPanicked)
        XCTAssertEqual(MermaidRenderFailure(status: MERMAID_ERR_FONT), .fontLoadFailed)
        XCTAssertEqual(MermaidRenderFailure(status: 99), .unknown(99))
    }

    /// A renderer panic must come back as an error, not take the process
    /// down — this library is loaded into a sandboxed Quick Look extension
    /// where a crash is a blank preview. The guard itself is exercised by
    /// `guarded_turns_a_panic_into_an_error_code` in the Rust crate, which
    /// can drive a panicking closure through it; this asserts the Swift side
    /// has a home for the answer when it comes back.
    func testAPanicHasAFailureToLandIn() {
        XCTAssertEqual(MermaidRenderFailure(status: MERMAID_ERR_PANIC), .rendererPanicked)
        XCTAssertNotEqual(MermaidRenderFailure(status: MERMAID_ERR_PANIC), .renderFailed)
    }
}

private extension Result where Failure == MermaidRenderFailure {
    var failureValue: MermaidRenderFailure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
