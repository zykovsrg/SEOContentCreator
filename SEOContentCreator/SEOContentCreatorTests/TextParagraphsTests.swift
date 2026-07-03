import Testing
import Foundation
@testable import SEOContentCreator

struct TextParagraphsTests {
    @Test func splitsOnBlankLines() {
        let text = "Первый абзац.\n\nВторой абзац.\n\nТретий."
        let ranges = TextParagraphs.ranges(in: text)
        #expect(ranges.count == 3)
        #expect(text[ranges[0]] == "Первый абзац.")
        #expect(text[ranges[1]] == "Второй абзац.")
        #expect(text[ranges[2]] == "Третий.")
    }

    @Test func singleParagraphWithoutBlankLines() {
        let text = "Только один абзац без разрывов."
        let ranges = TextParagraphs.ranges(in: text)
        #expect(ranges.count == 1)
        #expect(text[ranges[0]] == text[text.startIndex...])
    }

    @Test func emptyTextHasNoRanges() {
        #expect(TextParagraphs.ranges(in: "").isEmpty)
    }

    @Test func indexOfFindsContainingParagraph() {
        let text = "Первый абзац.\n\nВторой абзац с фразой тут.\n\nТретий."
        let ranges = TextParagraphs.ranges(in: text)
        let needleRange = text.range(of: "фразой тут")!
        #expect(TextParagraphs.index(of: needleRange.lowerBound, in: ranges) == 1)
    }

    @Test func indexOfReturnsNilOutOfBounds() {
        let text = "Абзац."
        let ranges = TextParagraphs.ranges(in: text)
        #expect(TextParagraphs.index(of: text.startIndex, in: []) == nil)
        _ = ranges
    }
}
