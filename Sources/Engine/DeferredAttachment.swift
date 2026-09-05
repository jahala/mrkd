import AppKit

extension NSAttributedString.Key {
    /// Which kind of deferred content an attachment stands in for — the
    /// raw value of `DeferredAttachmentKind`.
    static let deferredAttachmentKind = NSAttributedString.Key("MrkdDeferredKind")

    /// What that content is made from: an image's URL string, a
    /// formula's LaTeX, or a diagram's Mermaid source.
    static let deferredAttachmentSource = NSAttributedString.Key("MrkdDeferredSource")
}

/// The kinds of content `MarkdownRenderer` cannot finish on the spot.
enum DeferredAttachmentKind: String {
    /// A linked image, loaded from disk or the network.
    case image
    /// `$…$`, rendered onto the surrounding text's baseline.
    case inlineMath
    /// `$$…$$`, rendered centred on a line of its own.
    case displayMath
    /// A ```` ```mermaid ```` block, rasterised in the document's own colours.
    case diagram
}

/// Content the renderer leaves as a placeholder for the view to fill in.
///
/// One concept for every deferred thing in the document. `MarkdownRenderer`
/// emits an `NSTextAttachment` stamped with a kind and a source;
/// `MarkdownViewController` walks the finished text once and hands each one
/// to the provider for its kind. Images, math and Mermaid diagrams are all
/// the same shape — a source string that resolves to a bitmap,
/// asynchronously, cached, re-rendered when the theme or the scale changes —
/// so each costs a case, a provider, and a branch in one switch, rather than
/// a pipeline of its own.
struct DeferredAttachment: Equatable {
    let kind: DeferredAttachmentKind
    let source: String

    var attributes: [NSAttributedString.Key: Any] {
        [
            .deferredAttachmentKind: kind.rawValue,
            .deferredAttachmentSource: source,
        ]
    }

    /// Every deferred attachment in `text`, with the range each occupies,
    /// in document order.
    static func all(
        in text: NSAttributedString
    ) -> [(attachment: DeferredAttachment, range: NSRange)] {
        var found: [(attachment: DeferredAttachment, range: NSRange)] = []
        text.enumerateAttribute(
            .deferredAttachmentKind,
            in: NSRange(location: 0, length: text.length),
            options: []
        ) { value, range, _ in
            guard let raw = value as? String,
                  let kind = DeferredAttachmentKind(rawValue: raw),
                  let source = text.attribute(
                      .deferredAttachmentSource,
                      at: range.location,
                      effectiveRange: nil
                  ) as? String
            else { return }
            found.append((DeferredAttachment(kind: kind, source: source), range))
        }
        return found
    }
}
