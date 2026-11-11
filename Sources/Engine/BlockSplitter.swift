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
        var lines = raw.components(separatedBy: "\n")

        // Front matter is one block, blank lines and all.
        if let count = frontMatterLineCount(in: raw) {
            result.append(lines[..<count].joined(separator: "\n"))
            lines.removeFirst(count)
        }

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

    /// How many lines the YAML front matter at the start of `raw` takes,
    /// both delimiters included, or nil when there is none.
    ///
    /// This follows the convention GitHub, Jekyll and Obsidian share: the
    /// very first line is `---`, and the next line that is `---` or `...`
    /// closes it. Anywhere else, `---` is a rule or a heading underline. An
    /// opening line with nothing to close it is a rule too.
    static func frontMatterLineCount(in raw: String) -> Int? {
        let start = raw.hasPrefix("\u{FEFF}") ? raw.dropFirst() : Substring(raw)
        guard start.hasPrefix("---") else { return nil }

        let lines = start.components(separatedBy: "\n")
        func bare(_ line: String) -> String { line.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard bare(lines[0]) == "---" else { return nil }
        for index in lines.indices.dropFirst() where bare(lines[index]) == "---" || bare(lines[index]) == "..." {
            return index + 1
        }
        return nil
    }

    /// 1-based line number at which each block begins once the blocks are
    /// joined by a blank line — which is exactly the string `MarkdownRenderer`
    /// hands to cmark. Pairs with `blockIndex(forLine:startLines:)` to turn a
    /// parsed node's source line back into the block it came from.
    static func startLines(joining blocks: [String]) -> [Int] {
        var starts: [Int] = []
        starts.reserveCapacity(blocks.count)
        var line = 1
        for block in blocks {
            starts.append(line)
            line += block.components(separatedBy: "\n").count + 1
        }
        return starts
    }

    /// Index of the block containing the given 1-based source line, or nil
    /// when the line precedes every block (or there are no blocks).
    static func blockIndex(forLine line: Int, startLines: [Int]) -> Int? {
        guard let first = startLines.first, line >= first else { return nil }
        var low = 0
        var high = startLines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if startLines[mid] <= line {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
