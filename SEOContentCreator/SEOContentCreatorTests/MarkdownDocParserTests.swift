import Testing
@testable import SEOContentCreator

struct MarkdownDocParserTests {
    @Test func parsesHeadings() {
        let blocks = MarkdownDocParser.parse("# Заголовок\n## Подзаголовок\n### Мелкий")
        #expect(blocks.count == 3)
        #expect(blocks[0].style == .heading1 && blocks[0].text == "Заголовок")
        #expect(blocks[1].style == .heading2 && blocks[1].text == "Подзаголовок")
        #expect(blocks[2].style == .heading3 && blocks[2].text == "Мелкий")
    }

    @Test func parsesParagraph() {
        let blocks = MarkdownDocParser.parse("Просто абзац текста.")
        #expect(blocks.count == 1)
        #expect(blocks[0].style == .normal)
        #expect(blocks[0].listType == nil)
        #expect(blocks[0].text == "Просто абзац текста.")
    }

    @Test func parsesBulletAndNumberedLists() {
        let blocks = MarkdownDocParser.parse("- один\n- два\n1. первый\n2. второй")
        #expect(blocks[0].listType == .bullet && blocks[0].text == "один")
        #expect(blocks[1].listType == .bullet && blocks[1].text == "два")
        #expect(blocks[2].listType == .numbered && blocks[2].text == "первый")
        #expect(blocks[3].listType == .numbered && blocks[3].text == "второй")
    }

    @Test func extractsBoldRangesAndStripsMarkers() {
        let blocks = MarkdownDocParser.parse("Это **жирное** слово")
        #expect(blocks[0].text == "Это жирное слово")
        #expect(blocks[0].boldRanges == [4..<10]) // "жирное"
    }

    @Test func skipsBlankLines() {
        let blocks = MarkdownDocParser.parse("Первый\n\nВторой")
        #expect(blocks.count == 2)
        #expect(blocks[0].text == "Первый")
        #expect(blocks[1].text == "Второй")
    }
}
