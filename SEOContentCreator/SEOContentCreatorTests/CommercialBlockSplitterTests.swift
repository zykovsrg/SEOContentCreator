import Testing
@testable import SEOContentCreator

struct CommercialBlockSplitterTests {
    @Test func noMarkersReturnsOneSegment() {
        let result = CommercialBlockSplitter.split("Обычный текст статьи.")
        #expect(result == [TextSegment(isCommercial: false, text: "Обычный текст статьи.")])
    }

    @Test func singleBlockInTheMiddle() {
        let text = "До блока.\n\n[[БЛОК]]\nТекст блока.\n[[/БЛОК]]\n\nПосле блока."
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [
            TextSegment(isCommercial: false, text: "До блока."),
            TextSegment(isCommercial: true, text: "Текст блока."),
            TextSegment(isCommercial: false, text: "После блока.")
        ])
    }

    @Test func multipleBlocks() {
        let text = "[[БЛОК]]\nПервый.\n[[/БЛОК]]\nМежду.\n[[БЛОК]]\nВторой.\n[[/БЛОК]]"
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [
            TextSegment(isCommercial: true, text: "Первый."),
            TextSegment(isCommercial: false, text: "Между."),
            TextSegment(isCommercial: true, text: "Второй.")
        ])
    }

    @Test func blockAtVeryStartAndEnd() {
        let text = "[[БЛОК]]\nС начала.\n[[/БЛОК]]"
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [TextSegment(isCommercial: true, text: "С начала.")])
    }

    @Test func unmatchedOpenMarkerIsKeptAsLiteralText() {
        let text = "Текст [[БЛОК]] без закрытия."
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [TextSegment(isCommercial: false, text: "Текст [[БЛОК]] без закрытия.")])
    }

    @Test func emptyTextReturnsNoSegments() {
        #expect(CommercialBlockSplitter.split("") == [])
    }

    @Test func whitespaceOnlyGapBetweenBlocksProducesNoSpuriousSegment() {
        let text = "[[БЛОК]]\nA.\n[[/БЛОК]]\n\n\n[[БЛОК]]\nB.\n[[/БЛОК]]"
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [
            TextSegment(isCommercial: true, text: "A."),
            TextSegment(isCommercial: true, text: "B.")
        ])
    }
}
