import Foundation

/// Which markdown source blocks changed between two versions of a document,
/// and where those blocks ended up in the rendered text.
///
/// Pure value-in/value-out: no views, no layout, no file I/O. The view
/// controller supplies the two source strings and the rendered ranges, and
/// gets back the ranges to flash.
enum BlockDiff {

    /// A contiguous run of rendered text produced by one top-level parsed
    /// block, tagged with the index of the source block it started in.
    struct RenderedBlock: Equatable {
        let sourceIndex: Int
        let range: NSRange

        init(sourceIndex: Int, range: NSRange) {
            self.sourceIndex = sourceIndex
            self.range = range
        }
    }

    /// Indices into `new` that were inserted or modified relative to `old`,
    /// in ascending order.
    ///
    /// Deletions contribute nothing: a block that no longer exists has no
    /// index in `new` to point at, and every surviving block around it is
    /// genuinely unchanged.
    ///
    /// `maxComparisons` bounds the alignment step. Common head and tail are
    /// trimmed first, so an agent editing one paragraph of a large document
    /// leaves a middle of one or two blocks. When the differing middle is
    /// larger than the budget the blocks have diverged so far that aligning
    /// them says nothing useful, and the whole differing region is reported.
    static func changedIndices(
        from old: [String],
        to new: [String],
        maxComparisons: Int = 1_000_000
    ) -> [Int] {
        guard !new.isEmpty else { return [] }

        let limit = min(old.count, new.count)
        var prefix = 0
        while prefix < limit && old[prefix] == new[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < limit - prefix
            && old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }

        let oldMiddle = Array(old[prefix..<(old.count - suffix)])
        let newMiddle = Array(new[prefix..<(new.count - suffix)])

        guard !newMiddle.isEmpty else { return [] }
        guard !oldMiddle.isEmpty,
              oldMiddle.count * newMiddle.count <= maxComparisons
        else {
            return Array(prefix..<(prefix + newMiddle.count))
        }

        let matched = matchedNewIndices(old: oldMiddle, new: newMiddle)
        return newMiddle.indices
            .filter { !matched.contains($0) }
            .map { $0 + prefix }
    }

    /// Ranges of rendered text to flash, given the changed source blocks.
    ///
    /// A single parsed block can span several source blocks — a bullet list
    /// with blank lines between its items is one cmark node but three
    /// `BlockSplitter` blocks — so each rendered block covers every source
    /// index from its own up to the next rendered block's.
    static func highlightRanges(
        changed: Set<Int>,
        rendered: [RenderedBlock],
        sourceBlockCount: Int
    ) -> [NSRange] {
        guard !changed.isEmpty else { return [] }

        return rendered.indices.compactMap { position in
            let block = rendered[position]
            let upperBound: Int
            if position + 1 < rendered.count {
                upperBound = max(rendered[position + 1].sourceIndex, block.sourceIndex + 1)
            } else {
                upperBound = max(sourceBlockCount, block.sourceIndex + 1)
            }
            let covered = block.sourceIndex..<upperBound
            return covered.contains(where: { changed.contains($0) }) ? block.range : nil
        }
    }

    // MARK: - Longest common subsequence

    /// Indices into `new` that pair with an identical block in `old` under a
    /// longest-common-subsequence alignment. Everything else is a change.
    private static func matchedNewIndices(old: [String], new: [String]) -> Set<Int> {
        let rows = old.count
        let columns = new.count

        // lengths[row * (columns + 1) + column] = LCS length of the suffixes
        // old[row...] and new[column...].
        var lengths = [Int32](repeating: 0, count: (rows + 1) * (columns + 1))
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for column in stride(from: columns - 1, through: 0, by: -1) {
                let index = row * (columns + 1) + column
                if old[row] == new[column] {
                    lengths[index] = lengths[index + columns + 2] + 1
                } else {
                    lengths[index] = max(lengths[index + columns + 1], lengths[index + 1])
                }
            }
        }

        var matched = Set<Int>()
        var row = 0
        var column = 0
        while row < rows && column < columns {
            if old[row] == new[column] {
                matched.insert(column)
                row += 1
                column += 1
            } else if lengths[(row + 1) * (columns + 1) + column]
                >= lengths[row * (columns + 1) + column + 1] {
                row += 1
            } else {
                column += 1
            }
        }
        return matched
    }
}
