import Testing
@testable import SEOContentCreator

struct StageOutputParserTests {
    @Test func draftStageReturnsBodyOnly() {
        let raw = "H1\n\nТело статьи"
        let out = StageOutputParser.parse(rawText: raw, stage: .draft)
        #expect(out.body == "H1\n\nТело статьи")
        #expect(out.h1 == nil)
        #expect(out.seoTitle == nil)
    }

    @Test func semanticsStageExtractsTrailingJSON() {
        let raw = """
        Тело статьи с ключами.

        ```json
        {"h1":"Рак простаты","seoTitle":"Лечение рака простаты","seoDescription":"Описание","embeddedQueries":["рак простаты"],"notes":"всё ок"}
        ```
        """
        let out = StageOutputParser.parse(rawText: raw, stage: .semanticsInText)
        #expect(out.body == "Тело статьи с ключами.")
        #expect(out.h1 == "Рак простаты")
        #expect(out.seoTitle == "Лечение рака простаты")
        #expect(out.seoDescription == "Описание")
        #expect(out.embeddedQueries == ["рак простаты"])
        #expect(out.notes == "всё ок")
    }

    @Test func semanticsStageWithoutJSONReturnsBody() {
        let raw = "Просто текст без метаданных"
        let out = StageOutputParser.parse(rawText: raw, stage: .semanticsInText)
        #expect(out.body == "Просто текст без метаданных")
        #expect(out.h1 == nil)
    }
}
