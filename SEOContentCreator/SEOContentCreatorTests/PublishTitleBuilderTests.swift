import Testing
@testable import SEOContentCreator

struct PublishTitleBuilderTests {
    @Test func buildsTitleWithID() {
        let t = PublishTitleBuilder.title(externalID: "42", topicTitle: "Лечение мигрени")
        #expect(t == "№42 Лечение мигрени — Контент для страницы")
    }

    @Test func omitsNumberPrefixWhenIDEmpty() {
        let t = PublishTitleBuilder.title(externalID: "", topicTitle: "Лечение мигрени")
        #expect(t == "Лечение мигрени — Контент для страницы")
    }

    @Test func trimsWhitespace() {
        let t = PublishTitleBuilder.title(externalID: "  7 ", topicTitle: "  Тема  ")
        #expect(t == "№7 Тема — Контент для страницы")
    }
}
