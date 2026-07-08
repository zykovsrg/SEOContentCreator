import Testing
@testable import SEOContentCreator

struct EditorMetricsTests {
    @Test func countsCharactersWordsAndCommercialBlocks() {
        let text = """
        # Заголовок

        Один два три.

        [[БЛОК]]
        Оставьте номер телефона.
        [[/БЛОК]]
        """

        let metrics = EditorMetrics.compute(text: text, targetVolume: 100)
        let visibleText = "Заголовок\n\nОдин два три.\n\nОставьте номер телефона."

        #expect(metrics.charactersWithSpaces == visibleText.count)
        #expect(metrics.words == 7)
        #expect(metrics.commercialBlocks == 1)
        #expect(metrics.progress == Double(visibleText.count) / 100.0)
    }

    @Test func clampsProgressWhenTargetIsMissingOrExceeded() {
        #expect(EditorMetrics.compute(text: "Текст", targetVolume: nil).progress == nil)
        #expect(EditorMetrics.compute(text: "123456", targetVolume: 3).progress == 1)
    }
}
