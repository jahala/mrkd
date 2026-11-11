import XCTest
@testable import mrkd

final class BlockSplitterTests: XCTestCase {

    func testEmptyInputProducesEmptyArray() {
        XCTAssertEqual(BlockSplitter.split(""), [])
    }

    func testSingleParagraph() {
        XCTAssertEqual(BlockSplitter.split("hello world"), ["hello world"])
    }

    func testBlankLineSeparatesBlocks() {
        let input = "first\n\nsecond"
        XCTAssertEqual(BlockSplitter.split(input), ["first", "second"])
    }

    func testFencedCodeBlockIsNotSplitOnBlankLine() {
        let input = """
        ```
        line one

        line three
        ```
        """
        let result = BlockSplitter.split(input)
        XCTAssertEqual(result.count, 1, "fenced block must stay as one block despite internal blank line")
        XCTAssertTrue(result[0].contains("line one"))
        XCTAssertTrue(result[0].contains("line three"))
    }

    func testTildeFencedCodeBlockIsNotSplit() {
        let input = """
        ~~~
        line one

        line three
        ~~~
        """
        let result = BlockSplitter.split(input)
        XCTAssertEqual(result.count, 1)
    }

    func testParagraphBeforeAndAfterFencedBlock() {
        let input = """
        prose before

        ```
        code

        more code
        ```

        prose after
        """
        let result = BlockSplitter.split(input)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], "prose before")
        XCTAssertTrue(result[1].hasPrefix("```"))
        XCTAssertEqual(result[2], "prose after")
    }

    func testMultipleConsecutiveBlankLinesCollapse() {
        XCTAssertEqual(BlockSplitter.split("a\n\n\n\nb"), ["a", "b"])
    }

    // MARK: - Source line mapping

    func testStartLinesLocatesEachBlockInTheJoinedSource() {
        let blocks = ["# Title", "First paragraph.", "```\ncode\n\nmore\n```", "Last."]
        let starts = BlockSplitter.startLines(joining: blocks)
        XCTAssertEqual(starts, [1, 3, 5, 11])

        // Cross-check against the string the renderer actually parses.
        let joined = blocks.joined(separator: "\n\n")
        let lines = joined.components(separatedBy: "\n")
        XCTAssertEqual(lines[starts[0] - 1], "# Title")
        XCTAssertEqual(lines[starts[1] - 1], "First paragraph.")
        XCTAssertEqual(lines[starts[2] - 1], "```")
        XCTAssertEqual(lines[starts[3] - 1], "Last.")
    }

    func testStartLinesOfNoBlocksIsEmpty() {
        XCTAssertEqual(BlockSplitter.startLines(joining: []), [])
    }

    func testBlockIndexFindsTheBlockContainingALine() {
        let starts = [1, 3, 5, 11]
        XCTAssertEqual(BlockSplitter.blockIndex(forLine: 1, startLines: starts), 0)
        XCTAssertEqual(BlockSplitter.blockIndex(forLine: 2, startLines: starts), 0)
        XCTAssertEqual(BlockSplitter.blockIndex(forLine: 3, startLines: starts), 1)
        XCTAssertEqual(BlockSplitter.blockIndex(forLine: 7, startLines: starts), 2)
        XCTAssertEqual(BlockSplitter.blockIndex(forLine: 11, startLines: starts), 3)
        XCTAssertEqual(BlockSplitter.blockIndex(forLine: 999, startLines: starts), 3)
    }

    func testBlockIndexIsNilWhenThereIsNothingToPointAt() {
        XCTAssertNil(BlockSplitter.blockIndex(forLine: 4, startLines: []))
        XCTAssertNil(BlockSplitter.blockIndex(forLine: 0, startLines: [1, 3]))
    }

    // MARK: - Front matter

    /// YAML front matter may hold blank lines. It is one block, or the
    /// changed-block highlight and the renderer would each see its halves
    /// as separate paragraphs.
    func testFrontMatterIsOneBlockEvenWithABlankLineInside() {
        let source = "---\ntitle: Plan\n\ntags: [a, b]\n---\n\n# Heading"
        XCTAssertEqual(
            BlockSplitter.split(source),
            ["---\ntitle: Plan\n\ntags: [a, b]\n---", "# Heading"]
        )
    }

    func testFrontMatterIsFoundOnlyAtTheVeryStart() {
        XCTAssertEqual(BlockSplitter.frontMatterLineCount(in: "---\nkey: v\n---\nBody"), 3)
        XCTAssertEqual(BlockSplitter.frontMatterLineCount(in: "---\nkey: v\n...\nBody"), 3)
        XCTAssertEqual(BlockSplitter.frontMatterLineCount(in: "\u{FEFF}---\r\nkey: v\r\n---\r\n"), 3)
        // Later in the document, `---` is a rule and is left to cmark.
        XCTAssertNil(BlockSplitter.frontMatterLineCount(in: "Intro\n\n---\nkey: v\n---"))
        // An opening line with nothing to close it is a rule, not front matter.
        XCTAssertNil(BlockSplitter.frontMatterLineCount(in: "---\nkey: v\n\nBody"))
        XCTAssertNil(BlockSplitter.frontMatterLineCount(in: "----\nkey: v\n----"))
    }
}
