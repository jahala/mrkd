import AppKit

struct TOCEntry: Hashable {
    let level: Int
    let text: String
    let location: Int
}

enum TOCBuilder {
    static func build(from storage: NSAttributedString) -> [TOCEntry] {
        var out: [TOCEntry] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.accessibilityHeadingLevel, in: full) { value, range, _ in
            guard let level = value as? Int else { return }
            let text = storage.attributedSubstring(from: range).string
                .trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(TOCEntry(level: level, text: text, location: range.location))
        }
        return out
    }
}
