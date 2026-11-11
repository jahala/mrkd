import Foundation

/// XML-style tag pairs that coding agents wrap around parts of their output,
/// such as `<thinking>` … `</thinking>` or `<example index="1">` …
/// `</example>`. mrkd shows each pair as a labelled box.
///
/// A pair counts only when each tag stands alone on its own line at the left
/// margin, outside fenced code, and its name is not an HTML element. Real
/// HTML keeps rendering exactly as it did, and a tag with no partner stays
/// the text it was.
enum AgentTags {

    struct Pair: Equatable {
        /// The tag name as written, without attributes.
        let name: String
        /// Index of the opening tag's line.
        let open: Int
        /// Index of the closing tag's line.
        let close: Int
    }

    /// Every tag pair in `lines`, ordered by where it opens.
    ///
    /// Each close pairs with the nearest open of the same name. Opens it
    /// passes over are left unpaired, so pairs never cross: they nest or
    /// follow each other, which is what lets them render as boxes.
    ///
    /// - Parameter isCode: true for lines that belong to fenced code, which
    ///   are never tags.
    static func pairs(in lines: [String], isCode: (Int) -> Bool = { _ in false }) -> [Pair] {
        var openTags: [(name: String, line: Int)] = []
        var pairs: [Pair] = []
        for (index, line) in lines.enumerated() where !isCode(index) {
            if let name = openingName(line) {
                openTags.append((name, index))
            } else if let name = closingName(line),
                      let match = openTags.lastIndex(where: { $0.name == name }) {
                pairs.append(Pair(name: name, open: openTags[match].line, close: index))
                openTags.removeSubrange(match...)
            }
        }
        return pairs.sorted { $0.open < $1.open }
    }

    // MARK: - Tag lines

    // An XML name in ASCII: a letter or underscore, then letters, digits,
    // `_`, `-`, `.` or `:`. Attributes follow XML and HTML: a name, then
    // optionally `=` and a quoted or bare value. Nothing else may share the
    // line, which is what keeps inline tags inside a sentence out of this.
    private static let openingTag =
        #/<([A-Za-z_][A-Za-z0-9_.:\-]*)(?:[ \t]+[A-Za-z_:][A-Za-z0-9_.:\-]*(?:[ \t]*=[ \t]*(?:"[^"\n]*"|'[^'\n]*'|[^ \t\n"'=<>`]+))?)*[ \t]*>[ \t\r]*/#
    private static let closingTag =
        #/<\/([A-Za-z_][A-Za-z0-9_.:\-]*)[ \t]*>[ \t\r]*/#

    private static func openingName(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: openingTag) else { return nil }
        let name = String(match.1)
        return isHTMLElement(name) ? nil : name
    }

    private static func closingName(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: closingTag) else { return nil }
        let name = String(match.1)
        return isHTMLElement(name) ? nil : name
    }

    // MARK: - Reasoning

    /// Tags that hold an agent's reasoning rather than what it hands over.
    /// They render muted, the way agent apps show thinking.
    static func isReasoning(_ name: String) -> Bool {
        reasoningNames.contains(name.lowercased())
    }

    private static let reasoningNames: Set<String> = [
        "thinking", "think", "thought", "thoughts", "reasoning", "scratchpad", "reflection",
    ]

    // MARK: - HTML elements

    /// HTML tag names are case-insensitive, so `<DIV>` is still a div.
    static func isHTMLElement(_ name: String) -> Bool {
        htmlElements.contains(name.lowercased())
    }

    /// Every element the HTML Standard defines, from its index of elements,
    /// plus `math` and `svg`, which it lists from MathML and SVG, plus every
    /// element its "obsolete features" section names, since browsers and
    /// older pages still use them.
    /// https://html.spec.whatwg.org/multipage/indices.html#elements-3
    /// https://html.spec.whatwg.org/multipage/obsolete.html#non-conforming-features
    private static let htmlElements: Set<String> = [
        // Current elements.
        "a", "abbr", "address", "area", "article", "aside", "audio",
        "b", "base", "bdi", "bdo", "blockquote", "body", "br", "button",
        "canvas", "caption", "cite", "code", "col", "colgroup",
        "data", "datalist", "dd", "del", "details", "dfn", "dialog", "div", "dl", "dt",
        "em", "embed",
        "fieldset", "figcaption", "figure", "footer", "form",
        "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html",
        "i", "iframe", "img", "input", "ins",
        "kbd",
        "label", "legend", "li", "link",
        "main", "map", "mark", "math", "menu", "meta", "meter",
        "nav", "noscript",
        "object", "ol", "optgroup", "option", "output",
        "p", "picture", "pre", "progress",
        "q",
        "rp", "rt", "ruby",
        "s", "samp", "script", "search", "section", "select", "selectedcontent",
        "slot", "small", "source", "span", "strong", "style", "sub", "summary", "sup", "svg",
        "table", "tbody", "td", "template", "textarea", "tfoot", "th", "thead",
        "time", "title", "tr", "track",
        "u", "ul",
        "var", "video",
        "wbr",
        // Obsolete elements.
        "acronym", "applet", "basefont", "bgsound", "big", "blink", "center",
        "dir", "font", "frame", "frameset", "isindex", "keygen", "listing",
        "marquee", "menuitem", "multicol", "nextid", "nobr", "noembed",
        "noframes", "param", "plaintext", "rb", "rtc", "spacer", "strike",
        "tt", "xmp",
    ]
}
