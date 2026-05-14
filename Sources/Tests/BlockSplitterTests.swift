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
}
