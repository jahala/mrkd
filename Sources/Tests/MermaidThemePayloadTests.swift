import XCTest
import AppKit
@testable import mrkd

/// The payload is the whole of the theming story: whatever it says is what
/// the diagram looks like, and it is also the cache key, so two themes that
/// produced the same payload would produce the same picture. These tests are
/// about the colours actually arriving, and about the transparency and
/// dynamic-colour cases that would otherwise reach merman as something it
/// refuses to parse.
final class MermaidThemePayloadTests: XCTestCase {

    private func roles(_ theme: Theme) -> [String: String] {
        MermaidThemePayload.roles(for: theme)
    }

    private func decoded(_ theme: Theme) -> [String: Any] {
        let json = MermaidThemePayload.json(for: theme)
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8)))
            as? [String: Any] ?? [:]
    }

    // MARK: - Colour conversion

    func testFlattenCompositesATranslucentColourOntoItsBackground() {
        let half = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5)
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

        let flattened = MermaidThemePayload.flatten(half, over: white)

        XCTAssertEqual(flattened.redComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(flattened.greenComponent, 0.5, accuracy: 0.001)
        XCTAssertEqual(flattened.blueComponent, 0.5, accuracy: 0.001)
        XCTAssertEqual(flattened.alphaComponent, 1.0, accuracy: 0.001)
    }

    func testFlattenOntoADarkBackgroundDarkensRatherThanLightens() {
        let half = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.25)
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

        let flattened = MermaidThemePayload.flatten(half, over: black)

        XCTAssertEqual(flattened.redComponent, 0.25, accuracy: 0.001)
    }

    func testFlattenLeavesAnOpaqueColourAlone() {
        let opaque = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)

        let flattened = MermaidThemePayload.flatten(
            opaque,
            over: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        )

        XCTAssertEqual(MermaidThemePayload.hex(flattened), MermaidThemePayload.hex(opaque))
    }

    func testFlattenResolvesADynamicSystemColour() {
        // .textColor has no sRGB components until it is resolved. Reaching
        // merman unresolved is how a diagram ends up the wrong colour.
        let flattened = MermaidThemePayload.flatten(
            .textColor,
            over: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        )

        XCTAssertEqual(flattened.alphaComponent, 1.0, accuracy: 0.001)
    }

    func testHexIsSixDigitUppercase() {
        XCTAssertEqual(
            MermaidThemePayload.hex(NSColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 1)),
            "#FF0080"
        )
        XCTAssertEqual(
            MermaidThemePayload.hex(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
            "#000000"
        )
    }

    func testHexClampsExtendedRangeComponents() {
        // Extended-range sRGB can hold components outside 0…1, and merman
        // rejects "#1G0000" rather than drawing something odd.
        XCTAssertEqual(
            MermaidThemePayload.hex(NSColor(srgbRed: 1.4, green: -0.3, blue: 0, alpha: 1)),
            "#FF0000"
        )
    }

    // MARK: - Roles

    func testEveryRoleIsAnOpaqueHexTriple() {
        let pattern = try! NSRegularExpression(pattern: "^#[0-9A-F]{6}$")
        for theme in [CatppuccinMochaTheme() as Theme, GitHubLight(), DefaultTheme()] {
            for (name, value) in roles(theme) {
                let range = NSRange(location: 0, length: (value as NSString).length)
                XCTAssertNotNil(
                    pattern.firstMatch(in: value, range: range),
                    "\(theme.name) role \(name) is \(value), which merman cannot parse"
                )
            }
        }
    }

    func testTheCanvasIsTheThemesOwnBackground() {
        let theme = CatppuccinMochaTheme()
        let expected = MermaidThemePayload.hex(
            MermaidThemePayload.flatten(
                theme.backgroundColor,
                over: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            )
        )

        XCTAssertEqual(roles(theme)["canvas"], expected)
    }

    func testADarkThemesSurfacesAreDarkAndALightThemesAreLight() {
        func brightness(_ hex: String) -> CGFloat {
            let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
            let r = CGFloat((value >> 16) & 0xFF) / 255
            let g = CGFloat((value >> 8) & 0xFF) / 255
            let b = CGFloat(value & 0xFF) / 255
            return 0.299 * r + 0.587 * g + 0.114 * b
        }

        // The bug this whole feature has to avoid is a white diagram in a
        // dark document, so the surface a node is filled with is asserted
        // directly rather than inferred from `appearance`.
        XCTAssertLessThan(brightness(roles(CatppuccinMochaTheme())["surface"]!), 0.4)
        XCTAssertGreaterThan(brightness(roles(GitHubLight())["surface"]!), 0.6)
    }

    func testTextIsLegibleAgainstTheSurfaceItSitsOn() {
        func brightness(_ hex: String) -> CGFloat {
            let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
            return 0.299 * CGFloat((value >> 16) & 0xFF) / 255
                + 0.587 * CGFloat((value >> 8) & 0xFF) / 255
                + 0.114 * CGFloat(value & 0xFF) / 255
        }

        for theme in [CatppuccinMochaTheme() as Theme, GitHubLight(), GitHubDark()] {
            let roles = roles(theme)
            let gap = abs(brightness(roles["text"]!) - brightness(roles["surface"]!))
            XCTAssertGreaterThan(
                gap, 0.25,
                "\(theme.name): node text and node fill are too close to read"
            )
        }
    }

    /// The bug this replaced: `surface-alt` came from the theme's table
    /// header colour, which is the code background at a different alpha. For a
    /// theme whose code background is translucent that moves away from the
    /// canvas, and for one whose background is opaque it moves toward it — so
    /// a sequence diagram's actors came out far lighter than the flowchart
    /// nodes in the same document. All three surfaces must now sit on the same
    /// side of the canvas, in the same order, in every theme.
    func testTheThreeSurfacesStayInOneFamilyInEveryTheme() {
        func distance(_ a: String, _ b: String) -> CGFloat {
            func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
                let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
                return (CGFloat((v >> 16) & 0xFF), CGFloat((v >> 8) & 0xFF), CGFloat(v & 0xFF))
            }
            let (r1, g1, b1) = rgb(a)
            let (r2, g2, b2) = rgb(b)
            return abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
        }

        for theme in [CatppuccinMochaTheme() as Theme, GitHubLight(), GitHubDark(),
                      MonokaiTheme(), DefaultTheme()] {
            let roles = roles(theme)
            let canvas = roles["canvas"]!
            let muted = distance(canvas, roles["surface-muted"]!)
            let surface = distance(canvas, roles["surface"]!)
            let alt = distance(canvas, roles["surface-alt"]!)

            XCTAssertLessThan(
                muted, surface,
                "\(theme.name): clusters stand out more than the nodes on them"
            )
            XCTAssertGreaterThan(
                alt, surface,
                "\(theme.name): sequence actors recede behind the flowchart nodes"
            )
        }
    }

    func testBlendCarriesPastItsTargetAndClamps() {
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let grey = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)

        XCTAssertEqual(MermaidThemePayload.hex(
            MermaidThemePayload.blend(black, toward: grey, by: 0.5)), "#404040")
        XCTAssertEqual(MermaidThemePayload.hex(
            MermaidThemePayload.blend(black, toward: grey, by: 1)), "#808080")
        // Past the target…
        XCTAssertEqual(MermaidThemePayload.hex(
            MermaidThemePayload.blend(black, toward: grey, by: 1.6)), "#CCCCCC")
        // …but never past what a colour can be.
        XCTAssertEqual(MermaidThemePayload.hex(
            MermaidThemePayload.blend(black, toward: grey, by: 4)), "#FFFFFF")
    }

    // MARK: - Which theme colour each role comes from

    /// Every role, against the theme colour it claims to come from.
    ///
    /// Without this, any role could be swapped for any other theme colour and
    /// nothing would notice — arrows could quietly stop using the accent, node
    /// fills could become the page background. The design decisions in
    /// `roles(for:)` are only decisions if something defends them.
    private func expectedRoles(for theme: Theme) -> [String: String] {
        let base = theme.isDark
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let canvas = MermaidThemePayload.flatten(theme.backgroundColor, over: base)
        let surface = MermaidThemePayload.flatten(theme.codeBackgroundColor, over: canvas)
        func from(_ color: NSColor) -> String {
            MermaidThemePayload.hex(MermaidThemePayload.flatten(color, over: canvas))
        }
        return [
            "canvas": MermaidThemePayload.hex(canvas),
            "edge-label-background": MermaidThemePayload.hex(canvas),
            "surface": MermaidThemePayload.hex(surface),
            "surface-alt": MermaidThemePayload.hex(
                MermaidThemePayload.blend(canvas, toward: surface, by: 1.6)),
            "surface-muted": MermaidThemePayload.hex(
                MermaidThemePayload.blend(canvas, toward: surface, by: 0.5)),
            "text": from(theme.textColor),
            "subtle-text": from(theme.blockquoteColor),
            "border": from(theme.tableBorderColor),
            "line": from(theme.accentColor),
            "error": from(theme.admonitionColor(type: .caution)),
            "warning": from(theme.admonitionColor(type: .warning)),
            "success": from(theme.admonitionColor(type: .tip)),
        ]
    }

    /// The theme colours the roles are drawn from must be distinct, or the
    /// mapping test below could pass while reading the wrong one.
    func testTheThemeColoursTheRolesComeFromAreDistinguishable() {
        let theme = CatppuccinMochaTheme()
        let sources: [(String, NSColor)] = [
            ("background", theme.backgroundColor),
            ("codeBackground", theme.codeBackgroundColor),
            ("text", theme.textColor),
            ("blockquote", theme.blockquoteColor),
            ("tableBorder", theme.tableBorderColor),
            ("accent", theme.accentColor),
            ("caution", theme.admonitionColor(type: .caution)),
            ("warning", theme.admonitionColor(type: .warning)),
            ("tip", theme.admonitionColor(type: .tip)),
        ]
        var seen: [String: String] = [:]
        for (name, color) in sources {
            let hex = MermaidThemePayload.hex(
                MermaidThemePayload.flatten(color, over: theme.backgroundColor))
            XCTAssertNil(
                seen[hex],
                "\(name) and \(seen[hex] ?? "") are both \(hex); swapping them would go unnoticed"
            )
            seen[hex] = name
        }
    }

    func testEachRoleComesFromTheThemeColourItClaims() {
        for theme in [CatppuccinMochaTheme() as Theme, GitHubDark(), MonokaiTheme(), SnazzyTheme()] {
            let actual = roles(theme)
            let expected = expectedRoles(for: theme)
            XCTAssertEqual(
                Set(actual.keys), Set(expected.keys),
                "\(theme.name): the roles sent and the roles pinned here have drifted apart"
            )
            for (role, value) in expected {
                XCTAssertEqual(
                    actual[role], value,
                    "\(theme.name): role \(role) is not the theme colour it is documented to be"
                )
            }
        }
    }

    /// Arrows in the theme's signature accent is a deliberate choice, not a
    /// leftover. Named on its own so that changing it is a decision someone
    /// has to make rather than something that slips through.
    func testEdgesUseTheThemesAccentAndNotItsBodyText() {
        let theme = CatppuccinMochaTheme()
        let canvas = MermaidThemePayload.flatten(
            theme.backgroundColor, over: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))

        XCTAssertEqual(
            roles(theme)["line"],
            MermaidThemePayload.hex(MermaidThemePayload.flatten(theme.accentColor, over: canvas))
        )
        XCTAssertNotEqual(
            roles(theme)["line"],
            MermaidThemePayload.hex(MermaidThemePayload.flatten(theme.textColor, over: canvas))
        )
    }

    /// The box behind an edge label exists to break the edge line where the
    /// text crosses it. Any colour other than the document's own turns it into
    /// a visible rectangle drawn around the label.
    func testEdgeLabelBackgroundIsExactlyTheCanvas() {
        for theme in [CatppuccinMochaTheme() as Theme, GitHubLight(), MonokaiTheme()] {
            let roles = roles(theme)
            XCTAssertEqual(
                roles["edge-label-background"], roles["canvas"],
                "\(theme.name): edge labels sit on a box that is not the page colour"
            )
        }
    }

    func testEveryRoleMermanNeedsIsNamed() {
        // merman falls back between roles, but only from ones that are set.
        // Dropping one of these silently un-themes a diagram family.
        let named = Set(roles(CatppuccinMochaTheme()).keys)
        for role in ["canvas", "surface", "surface-alt", "surface-muted",
                     "text", "subtle-text", "border", "line"] {
            XCTAssertTrue(named.contains(role), "role \(role) is not being sent")
        }
    }

    // MARK: - The payload

    func testAppearanceFollowsTheThemesDarkness() {
        XCTAssertEqual(decoded(CatppuccinMochaTheme())["appearance"] as? String, "dark")
        XCTAssertEqual(decoded(GitHubLight())["appearance"] as? String, "light")
    }

    func testTheBodyFontAndSizeAreCarriedInWithAGenericFallback() {
        let theme = CatppuccinMochaTheme(baseFontSize: 17, fontFamily: "Inter")

        // mrkd's typefaces are registered into this process only, so resvg
        // cannot find them; naming a generic family keeps the fallback
        // predictable instead of whatever face merman reaches first.
        XCTAssertEqual(decoded(theme)["fontFamily"] as? String, "Inter, sans-serif")
        XCTAssertEqual(decoded(theme)["fontSize"] as? String, "17px")
    }

    func testTwoDifferentThemesProduceDifferentPayloads() {
        XCTAssertNotEqual(
            MermaidThemePayload.json(for: CatppuccinMochaTheme()),
            MermaidThemePayload.json(for: GitHubLight())
        )
    }

    func testTheSameThemeProducesTheSamePayloadEveryTime() {
        // The cache is keyed on this string; an unstable key would mean every
        // live reload re-rasterises every diagram in the document.
        XCTAssertEqual(
            MermaidThemePayload.json(for: CatppuccinMochaTheme()),
            MermaidThemePayload.json(for: CatppuccinMochaTheme())
        )
    }

    func testChangingTheFontSizeChangesThePayload() {
        // Cmd-+ has to miss the cache, or diagrams would stay at the old size.
        XCTAssertNotEqual(
            MermaidThemePayload.json(for: CatppuccinMochaTheme(baseFontSize: 13)),
            MermaidThemePayload.json(for: CatppuccinMochaTheme(baseFontSize: 18))
        )
    }
}
