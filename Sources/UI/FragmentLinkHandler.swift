import Foundation

enum FragmentLinkHandler {
    /// GitHub-style heading slug: lowercase, drop everything that isn't a
    /// letter, digit, hyphen, or underscore, and collapse runs of
    /// whitespace into single hyphens. Idempotent for already-slug input
    /// so it can be applied to both the URL fragment and the heading
    /// text without thinking about which is which.
    ///
    /// Ported verbatim from mdv/ContentView.swift:2204 headingSlug.
    static func slugify(_ s: String) -> String {
        var out = ""
        var lastWasHyphen = false
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasHyphen = false
            } else if ch == "-" || ch == "_" {
                if !out.isEmpty {
                    out.append(ch)
                    lastWasHyphen = (ch == "-")
                }
            } else if ch.isWhitespace {
                if !out.isEmpty && !lastWasHyphen {
                    out.append("-")
                    lastWasHyphen = true
                }
            }
        }
        while out.last == "-" || out.last == "_" { out.removeLast() }
        return out
    }

    /// Look up a TOC entry whose slugified text matches the given fragment.
    /// Both sides are slugified before comparison so they normalize to the
    /// same form (handles "Foo Bar" vs "foo-bar" identity).
    static func resolve(fragment: String, in entries: [TOCEntry]) -> TOCEntry? {
        let target = slugify(fragment)
        return entries.first { slugify($0.text) == target }
    }
}
