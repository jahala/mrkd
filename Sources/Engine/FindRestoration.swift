import Foundation

/// The match a reader is sitting on, captured as a value so it outlives the
/// text storage it came from.
struct FindMatch: Equatable {
    /// The matched text itself, not the search string. The find bar's
    /// pattern is not readable from outside it, but the selection *is* the
    /// match — re-finding that literal is what puts the reader back.
    let text: String
    /// Where the match started in the document that is about to be replaced.
    let location: Int
}

/// Putting an in-flight search back on its match after the document
/// underneath it changed. The controller reads the selection and applies
/// the result; choosing which occurrence to land on happens here, over
/// values, so it can be tested without a window.
enum FindRestoration {

    /// Every occurrence of `needle` in `haystack`, in document order and
    /// non-overlapping. Case-insensitive, matching the find bar's default.
    static func matches(of needle: String, in haystack: String) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        let text = haystack as NSString
        var found: [NSRange] = []
        var start = 0
        while start < text.length {
            let range = text.range(
                of: needle,
                options: [.caseInsensitive],
                range: NSRange(location: start, length: text.length - start)
            )
            guard range.location != NSNotFound else { break }
            found.append(range)
            start = NSMaxRange(range)
        }
        return found
    }

    /// The occurrence to put the reader back on after a re-render.
    ///
    /// Character offsets do not survive an edit, so the rule is positional:
    /// the first occurrence at or after where the reader was. Text inserted
    /// above them pushes their match down and it is still the first one at
    /// or after the old offset, so they keep their place rather than being
    /// thrown back to the top of the document. When the edit removed
    /// everything below them, the last occurrence is the closest thing left.
    static func restoredMatch(for previous: FindMatch, in text: String) -> NSRange? {
        let all = matches(of: previous.text, in: text)
        guard !all.isEmpty else { return nil }
        return all.first { $0.location >= previous.location } ?? all.last
    }
}
