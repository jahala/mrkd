import Foundation

/// A math formula lifted out of markdown source before it reaches cmark.
struct MathSpan: Equatable {
    /// The LaTeX between the delimiters, trimmed, delimiters excluded.
    let latex: String
    /// `$$…$$` — its own centred line — rather than `$…$` on the text baseline.
    let isDisplay: Bool

    /// The formula as it was written. Shown verbatim when SwaTex cannot
    /// parse it, so a bad formula reads as source rather than as a gap.
    var literal: String {
        isDisplay ? "$$\(latex)$$" : "$\(latex)$"
    }
}

/// Lifts `$…$` and `$$…$$` out of markdown *before* anything else touches it,
/// leaving an opaque placeholder behind.
///
/// Running first is what makes the rest of the pipeline safe. Smart
/// typography would curl the prime in `$f'(x)$` into a quote; cmark would
/// eat the backslashes in `$$a \\ b$$` and read `$a*b*c$` as emphasis.
/// Neither ever sees the formula. The placeholder is Private Use Area
/// text: smart typography has no rule for it and cmark passes it through
/// as an ordinary word character, so it comes out the far end of the
/// render intact and `MarkdownRenderer` swaps an attachment back in.
///
/// The delimiter rules are pandoc's, tightened once: an opening `$` is
/// followed by a non-space, and a closing `$` is preceded by a non-space
/// and followed by neither a digit nor a letter. The digit half leaves
/// `$5 and $10` alone; the letter half leaves `$HOME/$USER` alone, which
/// matters in a viewer whose documents are mostly developer notes.
enum MathSpanScanner {

    /// Private Use Area. No real document contains these, and any that
    /// arrive in the source are dropped before a placeholder is written,
    /// so a document cannot forge one.
    private static let open: Character = "\u{E000}"
    private static let close: Character = "\u{E001}"
    private static let openUnit: unichar = 0xE000
    private static let closeUnit: unichar = 0xE001

    /// The placeholder standing in for the span at `index`.
    static func placeholder(_ index: Int) -> String {
        "\(open)\(index)\(close)"
    }

    /// Lift every formula out of one markdown block.
    ///
    /// - Parameter firstIndex: the number the first span found here gets.
    ///   Blocks are scanned in document order and share one numbering, so
    ///   the caller passes the running total.
    /// - Returns: the block with each formula replaced by its placeholder,
    ///   and the formulas in the order they were found.
    static func extract(
        from block: String,
        firstIndex: Int = 0
    ) -> (source: String, spans: [MathSpan]) {
        // An indented code block is verbatim, and `BlockSplitter` has
        // already made it a block of its own — its first line is the tell.
        guard !isIndentedCode(block) else { return (block, []) }

        let chars = Array(block)
        let fenced = fencedLines(chars)

        var out = ""
        out.reserveCapacity(chars.count)
        var spans: [MathSpan] = []

        var i = 0
        var line = 0
        /// Backtick-run length of the open inline code span, 0 when outside.
        var codeRun = 0

        while i < chars.count {
            let c = chars[i]

            if c == open || c == close {
                i += 1
                continue
            }

            if c == "\n" {
                out.append(c)
                line += 1
                i += 1
                continue
            }

            if fenced[line] {
                out.append(c)
                i += 1
                continue
            }

            if c == "`" {
                var run = 0
                var j = i
                while j < chars.count && chars[j] == "`" {
                    run += 1
                    j += 1
                }
                // A span closes on a run of exactly its own length.
                if codeRun == 0 {
                    codeRun = run
                } else if codeRun == run {
                    codeRun = 0
                }
                out.append(String(repeating: "`", count: run))
                i = j
                continue
            }

            if codeRun > 0 {
                out.append(c)
                i += 1
                continue
            }

            // `\$` is a literal dollar; cmark unescapes it later.
            if c == "\\", i + 1 < chars.count {
                out.append(c)
                out.append(chars[i + 1])
                i += 2
                continue
            }

            if c == "$" {
                if let match = displayMatch(chars, from: i) ?? inlineMatch(chars, from: i) {
                    out.append(placeholder(firstIndex + spans.count))
                    spans.append(match.span)
                    // A display formula can span lines the scan just skipped.
                    line += chars[i..<match.end].reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
                    i = match.end
                    continue
                }
            }

            out.append(c)
            i += 1
        }

        return (out, spans)
    }

    /// Every placeholder in `text`, in document order.
    static func placeholderRanges(in text: NSString) -> [(range: NSRange, index: Int)] {
        var found: [(range: NSRange, index: Int)] = []
        var i = 0
        while i < text.length {
            guard text.character(at: i) == openUnit else {
                i += 1
                continue
            }
            var j = i + 1
            var index = 0
            var digits = 0
            while j < text.length {
                let unit = text.character(at: j)
                guard unit >= 48, unit <= 57 else { break }
                index = index * 10 + Int(unit - 48)
                digits += 1
                j += 1
            }
            guard digits > 0, j < text.length, text.character(at: j) == closeUnit else {
                i += 1
                continue
            }
            found.append((NSRange(location: i, length: j + 1 - i), index))
            i = j + 1
        }
        return found
    }

    // MARK: - Delimiters

    private struct Match {
        let span: MathSpan
        /// Index just past the closing delimiter.
        let end: Int
    }

    /// `$$…$$`. May span lines, but must close inside the block.
    private static func displayMatch(_ chars: [Character], from i: Int) -> Match? {
        guard i + 1 < chars.count, chars[i + 1] == "$" else { return nil }
        var j = i + 2
        while j + 1 < chars.count {
            if chars[j] == "\\" {
                j += 2
                continue
            }
            if chars[j] == "$", chars[j + 1] == "$" {
                let latex = String(chars[(i + 2)..<j])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !latex.isEmpty else { return nil }
                return Match(span: MathSpan(latex: latex, isDisplay: true), end: j + 2)
            }
            j += 1
        }
        return nil
    }

    /// `$…$` on one line. TeX forbids a paragraph break inside inline math,
    /// and stopping at the newline is what keeps a list of prices from
    /// turning one stray `$` into a formula spanning two bullets.
    private static func inlineMatch(_ chars: [Character], from i: Int) -> Match? {
        guard i + 1 < chars.count else { return nil }
        let first = chars[i + 1]
        guard !first.isWhitespace, first != "$" else { return nil }

        var j = i + 1
        while j < chars.count {
            let c = chars[j]
            if c == "\n" { return nil }
            if c == "\\" {
                j += 2
                continue
            }
            if c == "$" {
                let previous = chars[j - 1]
                let next: Character? = j + 1 < chars.count ? chars[j + 1] : nil
                let followedByWord = next.map { $0.isNumber || $0.isLetter } ?? false
                if !previous.isWhitespace && !followedByWord {
                    let latex = String(chars[(i + 1)..<j])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !latex.isEmpty else { return nil }
                    return Match(span: MathSpan(latex: latex, isDisplay: false), end: j + 1)
                }
            }
            j += 1
        }
        return nil
    }

    // MARK: - Code

    /// Per-character flag: is this character inside a fenced code block?
    /// Indexed by line, mirroring `BlockSplitter`'s fence tracking so the
    /// two agree on where code starts and stops.
    private static func fencedLines(_ chars: [Character]) -> [Bool] {
        var flags: [Bool] = []
        var marker: String?
        for line in String(chars).components(separatedBy: "\n") {
            let body = line.drop(while: { $0 == " " })
            if let open = marker {
                flags.append(true)
                if body.hasPrefix(open) { marker = nil }
            } else if body.hasPrefix("```") {
                marker = "```"
                flags.append(true)
            } else if body.hasPrefix("~~~") {
                marker = "~~~"
                flags.append(true)
            } else {
                flags.append(false)
            }
        }
        return flags
    }

    private static func isIndentedCode(_ block: String) -> Bool {
        guard let first = block.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first else { return false }
        return first.hasPrefix("    ") || first.hasPrefix("\t")
    }
}
