import Testing
@testable import SEOContentCreator

struct RemarkRedoBuilderTests {
    @Test func promptIncludesAllInputs() {
        let prompt = RemarkRedoBuilder.build(
            category: "Вода", quote: "Записаться можно через клинику.",
            explanation: "Фраза не даёт полезной информации.", comment: "сделай короче, не удаляй совсем"
        )
        #expect(prompt.user.contains("Вода"))
        #expect(prompt.user.contains("Записаться можно через клинику."))
        #expect(prompt.user.contains("Фраза не даёт полезной информации."))
        #expect(prompt.user.contains("сделай короче, не удаляй совсем"))
    }
}

struct RemarkRedoParserTests {
    @Test func parsesFencedJSON() {
        let raw = """
        Вот доработанный вариант:
        ```json
        {"suggestion":"Новый текст"}
        ```
        """
        #expect(RemarkRedoParser.parse(rawText: raw) == "Новый текст")
    }

    @Test func parsesEmptySuggestionAsDeleteSignal() {
        let raw = "```json\n{\"suggestion\":\"\"}\n```"
        #expect(RemarkRedoParser.parse(rawText: raw) == "")
    }

    @Test func returnsNilForMalformedResponse() {
        #expect(RemarkRedoParser.parse(rawText: "not json at all") == nil)
    }

    @Test func parsesBareJSONWithoutFence() {
        #expect(RemarkRedoParser.parse(rawText: "{\"suggestion\":\"ок\"}") == "ок")
    }
}
