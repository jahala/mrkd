import XCTest
import AppKit
@testable import mrkd

final class BlockDiffTests: XCTestCase {

    // MARK: - changedIndices

    func testUnchangedSourceReportsNothing() {
        let blocks = ["# Title", "First paragraph.", "Second paragraph."]
        XCTAssertEqual(BlockDiff.changedIndices(from: blocks, to: blocks), [])
    }

    func testModifiedMiddleBlockReportsOnlyThatIndex() {
        let old = ["# Title", "First paragraph.", "Second paragraph.", "Third paragraph."]
        let new = ["# Title", "First paragraph.", "Second paragraph, rewritten.", "Third paragraph."]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [2])
    }

    /// The point of using a real subsequence diff rather than comparing
    /// position by position: everything after an insertion shifts down but
    /// has not changed, and must not be highlighted.
    func testInsertionInMiddleReportsOnlyTheInsertedIndex() {
        let old = ["# Title", "First paragraph.", "Second paragraph.", "Third paragraph."]
        let new = ["# Title", "First paragraph.", "Brand new paragraph.", "Second paragraph.", "Third paragraph."]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [2])
    }

    /// A deleted block has no index in the new document, and every surviving
    /// block is unchanged, so nothing is reported. Note this case is settled
    /// by the common head/tail trimming — it never reaches the alignment.
    /// `testDeletionSurroundedByEditsIsMatchedNotFlagged` covers that path.
    func testDeletionInMiddleReportsNothing() {
        let old = ["# Title", "First paragraph.", "Second paragraph.", "Third paragraph."]
        let new = ["# Title", "First paragraph.", "Third paragraph."]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [])
    }

    func testInsertionAtTopReportsOnlyTheNewBlock() {
        let old = ["First paragraph.", "Second paragraph."]
        let new = ["# Freshly added title", "First paragraph.", "Second paragraph."]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [0])
    }

    func testAppendReportsOnlyTheAppendedBlocks() {
        let old = ["# Title", "First paragraph."]
        let new = ["# Title", "First paragraph.", "Second paragraph.", "Third paragraph."]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [2, 3])
    }

    func testEmptyToContentReportsEveryBlock() {
        XCTAssertEqual(BlockDiff.changedIndices(from: [], to: ["a", "b", "c"]), [0, 1, 2])
    }

    func testContentToEmptyReportsNothing() {
        XCTAssertEqual(BlockDiff.changedIndices(from: ["a", "b", "c"], to: []), [])
    }

    func testWholesaleRewriteReportsEveryBlock() {
        let old = ["alpha", "beta", "gamma"]
        let new = ["one", "two"]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [0, 1])
    }

    /// Repeated identical blocks must not confuse the head/tail trimming.
    /// (The alignment proper is covered by `testRepeatedBlocksAreAlignedPairwise`.)
    func testRepeatedBlocksSurviveTrimming() {
        let old = ["---", "body", "---", "body", "---"]
        let new = ["---", "body", "---", "changed body", "---"]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [3])
    }

    /// Above the comparison budget the diff stops trying to align blocks and
    /// reports the whole differing region. The middle here *does* contain a
    /// shared block, so this only holds if the budget guard actually fires —
    /// the alignment would have spotted "same" and left it alone.
    func testOversizedDiffReportsTheWholeDifferingRegion() {
        let old = ["head", "x1", "same", "x2", "tail"]
        let new = ["head", "y1", "same", "y2", "tail"]
        XCTAssertEqual(
            BlockDiff.changedIndices(from: old, to: new, maxComparisons: 4),
            [1, 2, 3]
        )
    }

    /// The same input within budget: the shared block in the middle is found
    /// and left alone. Paired with the test above, this pins the budget guard
    /// from both sides.
    func testTheSameDiffWithinBudgetSparesTheSharedBlock() {
        let old = ["head", "x1", "same", "x2", "tail"]
        let new = ["head", "y1", "same", "y2", "tail"]
        XCTAssertEqual(
            BlockDiff.changedIndices(from: old, to: new, maxComparisons: 9),
            [1, 3]
        )
    }

    /// Common head and tail are trimmed before the expensive alignment, so a
    /// tiny edit inside a huge document stays cheap and still exact.
    func testLargeDocumentWithOneEditReportsOnlyThatEdit() {
        var old = (1...5_000).map { "Paragraph number \($0)." }
        var new = old
        new[2_500] = "Paragraph number 2501, rewritten by the agent."
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [2_500])
        old.removeAll()
        new.removeAll()
    }

    // MARK: - highlightRanges

    func testHighlightRangesPicksOutOnlyTheChangedRenderedBlocks() {
        let rendered = [
            BlockDiff.RenderedBlock(sourceIndex: 0, range: NSRange(location: 0, length: 10)),
            BlockDiff.RenderedBlock(sourceIndex: 1, range: NSRange(location: 10, length: 25)),
            BlockDiff.RenderedBlock(sourceIndex: 2, range: NSRange(location: 35, length: 15)),
        ]
        let ranges = BlockDiff.highlightRanges(changed: [1], rendered: rendered, sourceBlockCount: 3)
        XCTAssertEqual(ranges, [NSRange(location: 10, length: 25)])
    }

    /// One parsed block can cover several source blocks — a bullet list with
    /// blank lines between its items is a single cmark node spanning three
    /// `BlockSplitter` blocks. Changing any of them must light up the list.
    func testRenderedBlockCoversEverySourceBlockUpToTheNextOne() {
        let rendered = [
            BlockDiff.RenderedBlock(sourceIndex: 0, range: NSRange(location: 0, length: 8)),
            BlockDiff.RenderedBlock(sourceIndex: 1, range: NSRange(location: 8, length: 40)),
            BlockDiff.RenderedBlock(sourceIndex: 4, range: NSRange(location: 48, length: 12)),
        ]
        let ranges = BlockDiff.highlightRanges(changed: [3], rendered: rendered, sourceBlockCount: 5)
        XCTAssertEqual(ranges, [NSRange(location: 8, length: 40)])
    }

    func testLastRenderedBlockCoversTheTailOfTheSourceBlocks() {
        let rendered = [
            BlockDiff.RenderedBlock(sourceIndex: 0, range: NSRange(location: 0, length: 8)),
            BlockDiff.RenderedBlock(sourceIndex: 2, range: NSRange(location: 8, length: 30)),
        ]
        let ranges = BlockDiff.highlightRanges(changed: [4], rendered: rendered, sourceBlockCount: 5)
        XCTAssertEqual(ranges, [NSRange(location: 8, length: 30)])
    }

    func testNoChangedBlocksProducesNoRanges() {
        let rendered = [
            BlockDiff.RenderedBlock(sourceIndex: 0, range: NSRange(location: 0, length: 8)),
        ]
        XCTAssertEqual(BlockDiff.highlightRanges(changed: [], rendered: rendered, sourceBlockCount: 1), [])
    }

    // MARK: - Source block indices survive the render

    /// The whole feature hinges on being able to point at a changed source
    /// block in the rendered text. Render a real document and check that the
    /// third block's rendered range really does contain the third block's text.
    func testRendererTagsEachRenderedRangeWithItsSourceBlockIndex() {
        let source = "# Title\n\nFirst paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let rendered = MarkdownRenderer.render(source, theme: DefaultTheme())

        var tagged: [Int: NSRange] = [:]
        rendered.enumerateAttribute(
            .sourceBlockIndex,
            in: NSRange(location: 0, length: rendered.length),
            options: []
        ) { value, range, _ in
            if let index = value as? Int { tagged[index] = range }
        }

        XCTAssertEqual(tagged.count, 4, "every top-level block should be tagged")
        guard let third = tagged[3] else { return XCTFail("no range tagged for block 3") }
        XCTAssertTrue(
            rendered.attributedSubstring(from: third).string.contains("Third paragraph."),
            "block 3's tagged range should cover the third paragraph"
        )
        guard let title = tagged[0] else { return XCTFail("no range tagged for block 0") }
        XCTAssertTrue(rendered.attributedSubstring(from: title).string.contains("Title"))
    }

    /// A loose list is one cmark node but three source blocks; the node is
    /// tagged with the index of the block it starts in, and `highlightRanges`
    /// extends its coverage over the rest.
    func testLooseListIsTaggedWithItsFirstSourceBlock() {
        let source = "intro\n\n- one\n\n- two\n\n- three\n\noutro"
        let blocks = BlockSplitter.split(source)
        XCTAssertEqual(blocks.count, 5)

        let rendered = MarkdownRenderer.render(source, theme: DefaultTheme())
        var indices: [Int] = []
        rendered.enumerateAttribute(
            .sourceBlockIndex,
            in: NSRange(location: 0, length: rendered.length),
            options: []
        ) { value, _, _ in
            if let index = value as? Int { indices.append(index) }
        }
        XCTAssertEqual(indices, [0, 1, 4], "the three list items render as one tagged node")
    }

    // MARK: - Subsequence alignment
    //
    // Everything above is settled by trimming the common head and tail. These
    // reach the alignment itself: a middle where old and new both have
    // content and share some of it.

    /// The common agent case: two edits in one reload with an untouched block
    /// between them. Only the two edits are reported — without a real
    /// alignment the block in the middle is dragged in with them.
    func testTwoSeparatedEditsLeaveTheBlockBetweenThemAlone() {
        let old = ["intro", "first draft", "keep me", "second draft", "outro"]
        let new = ["intro", "first rewritten", "keep me", "second rewritten", "outro"]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [1, 3])
    }

    /// The surviving block is displaced rather than aligned: it moves from
    /// index 2 to index 1 because the block before it was removed and two new
    /// ones appended. It is still the same block and must not be flagged.
    func testUnchangedBlockDisplacedByAnEditIsStillMatched() {
        let old = ["intro", "dropped", "keep me", "replaced", "outro"]
        let new = ["intro", "keep me", "added one", "added two", "outro"]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [2, 3])
    }

    /// A deletion that the trimming cannot isolate, because the blocks on
    /// both sides of it changed too. The alignment has to recognise that the
    /// surviving middle block is unchanged.
    func testDeletionSurroundedByEditsIsMatchedNotFlagged() {
        let old = ["intro", "before", "keep me", "after", "outro"]
        let new = ["intro", "keep me", "outro"]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [])
    }

    /// Two identical blocks inside the changed middle must pair up one-to-one
    /// with the two identical blocks in the old middle, not collapse into a
    /// single match or none at all.
    func testRepeatedBlocksAreAlignedPairwise() {
        let old = ["intro", "old a", "---", "old b", "---", "old c", "outro"]
        let new = ["intro", "new a", "---", "new b", "---", "new c", "outro"]
        XCTAssertEqual(BlockDiff.changedIndices(from: old, to: new), [1, 3, 5])
    }
}
