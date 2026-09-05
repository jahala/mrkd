import Foundation

/// Identifies a heading well enough to find it again after a re-render.
/// Character offsets and scroll offsets both move when the text above them
/// changes length; a heading's text and level do not.
struct HeadingKey: Hashable {
    let text: String
    let level: Int
    /// 0-based ordinal among headings sharing the same text and level, so a
    /// document with three "## Notes" sections anchors to the right one.
    let occurrence: Int
}

/// A heading and where it currently sits in document coordinates.
struct HeadingPosition: Equatable {
    let key: HeadingKey
    let y: CGFloat
}

/// Where the reader was, expressed so it survives the document above them
/// growing or shrinking.
struct ScrollAnchor: Equatable {
    /// The last heading at or above the viewport top, if there was one.
    let heading: HeadingKey?
    /// Distance from that heading's top to the viewport top, in points.
    let offsetFromHeading: CGFloat
    /// Position within the scrollable range (0…1). Used when there was no
    /// heading to anchor to, or when the edit removed the anchored heading.
    let proportion: CGFloat
}

/// Pure reading-position arithmetic. Callers measure the headings (which
/// needs layout) and apply the resulting offset (which needs a scroll view);
/// everything in between is values.
enum ScrollAnchoring {

    /// Stable keys for a document's headings, in document order.
    static func keys(for entries: [TOCEntry]) -> [HeadingKey] {
        var seen: [String: Int] = [:]
        return entries.map { entry in
            let identity = "\(entry.level)\u{0}\(entry.text)"
            let occurrence = seen[identity, default: 0]
            seen[identity] = occurrence + 1
            return HeadingKey(text: entry.text, level: entry.level, occurrence: occurrence)
        }
    }

    /// Capture the reading position. `headings` must be in document order.
    ///
    /// `band` extends the search a little way into the viewport, so a heading
    /// sitting just below the top counts as the one the reader is under —
    /// the same rule the table of contents uses to decide which entry is
    /// active. Without it, clicking a TOC entry (which parks the heading a
    /// fifth of the way down) would anchor to the *previous* heading, far
    /// off screen, and any edit in between would drag the reader with it.
    static func anchor(
        headings: [HeadingPosition],
        viewportTop: CGFloat,
        band: CGFloat,
        maxScroll: CGFloat
    ) -> ScrollAnchor {
        let proportion = maxScroll > 0
            ? min(1, max(0, viewportTop / maxScroll))
            : 0

        guard let current = headings.last(where: { $0.y <= viewportTop + band }) else {
            return ScrollAnchor(heading: nil, offsetFromHeading: 0, proportion: proportion)
        }
        return ScrollAnchor(
            heading: current.key,
            offsetFromHeading: viewportTop - current.y,
            proportion: proportion
        )
    }

    /// Where to scroll after the re-render. `headingY` is the anchored
    /// heading's new position, or nil when the edit removed it — in which
    /// case the proportional position is the best remaining guess.
    ///
    /// Only the top is clamped. How far the document actually scrolls is the
    /// scroll view's to know, and it knows it later than this: immediately
    /// after a re-render the text view is still the previous document's
    /// height, so clamping here would drag the reader back up.
    static func offset(
        restoring anchor: ScrollAnchor,
        headingY: CGFloat?,
        maxScroll: CGFloat
    ) -> CGFloat {
        let target: CGFloat
        if anchor.heading != nil, let headingY {
            target = headingY + anchor.offsetFromHeading
        } else {
            target = anchor.proportion * max(0, maxScroll)
        }
        return max(0, target)
    }
}
