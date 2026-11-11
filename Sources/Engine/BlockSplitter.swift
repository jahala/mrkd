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
        let lines = raw.components(separatedBy: "\n")
        let fences = fenceRoles(of: lines)
        // An agent tag line that has a partner is a block of its own, so a
        // tight `<thinking>` … `</thinking>` parses the same as one with
        // blank lines around its content. See `AgentTags`.
        let tagLines = Set(
            AgentTags.pairs(in: lines, isCode: { fences[$0] != .outside })
                .flatMap { [$0.open, $0.close] }
        )

        func flush() {
            let joined = current.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !joined.isEmpty { result.append(joined) }
            current.removeAll(keepingCapacity: true)
        }

        for (index, line) in lines.enumerated() {
            switch fences[index] {
            case .opening:
                flush()
                current.append(line)
            case .inside:
                current.append(line)
            case .outside where tagLines.contains(index):
                flush()
                current.append(line)
                flush()
            case .outside:
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    flush()
                } else {
                    current.append(line)
                }
            }
        }
        flush()
        return result
    }

    private enum FenceRole {
        case outside
        /// The line that opens a fence.
        case opening
        /// A line inside a fence, its closing line included.
        case inside
    }

    /// Where each line stands relative to fenced code (``` or ~~~).
    private static func fenceRoles(of lines: [String]) -> [FenceRole] {
        var roles: [FenceRole] = []
        roles.reserveCapacity(lines.count)
        var fenceMarker: String? = nil  // nil → outside, "```" or "~~~" → inside
        for line in lines {
            let trimmedStart = line.drop(while: { $0 == " " })
            if let marker = fenceMarker {
                roles.append(.inside)
                if trimmedStart.hasPrefix(marker) {
                    fenceMarker = nil
                }
            } else if trimmedStart.hasPrefix("```") {
                roles.append(.opening)
                fenceMarker = "```"
            } else if trimmedStart.hasPrefix("~~~") {
                roles.append(.opening)
                fenceMarker = "~~~"
            } else {
                roles.append(.outside)
            }
        }
        return roles
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
