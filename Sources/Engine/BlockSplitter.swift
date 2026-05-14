import Foundation

enum BlockSplitter {
    /// Split markdown source into top-level blocks, respecting fenced code.
    /// A blank line ends a paragraph block normally, but blank lines inside
    /// a fenced code block (``` or ~~~) are part of the code and must not
    /// split the block — otherwise multi-paragraph code samples get
    /// shredded into separate single-line blocks.
    static func split(_ raw: String) -> [String] {
        // Fence-aware split. A blank line ends a paragraph block normally,
        // but blank lines INSIDE a fenced code block (``` or ~~~) are part
        // of the code and must not split the block — otherwise multi-
        // paragraph code samples get shredded into separate single-line
        // code-blocks-or-prose, which mangles syntax highlighting.
        var result: [String] = []
        var current: [String] = []
        var fenceMarker: String? = nil  // nil → outside, "```" or "~~~" → inside
        let lines = raw.components(separatedBy: "\n")

        func flush() {
            let joined = current.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !joined.isEmpty { result.append(joined) }
            current.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmedStart = line.drop(while: { $0 == " " })
            if let marker = fenceMarker {
                current.append(line)
                if trimmedStart.hasPrefix(marker) {
                    fenceMarker = nil
                }
                continue
            }
            if trimmedStart.hasPrefix("```") {
                if !current.isEmpty { flush() }
                current.append(line)
                fenceMarker = "```"
                continue
            }
            if trimmedStart.hasPrefix("~~~") {
                if !current.isEmpty { flush() }
                current.append(line)
                fenceMarker = "~~~"
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                current.append(line)
            }
        }
        flush()
        return result
    }
}
