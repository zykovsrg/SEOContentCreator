import Testing
@testable import SEOContentCreator

struct SemanticPromptRendererTests {
    @Test func rendersAcceptedAndRequiredOnly() {
        let topic = Topic(title: "Тест", articleType: .info)
        topic.semanticKeywords = [
            SemanticKeyword(text: "МРТ лёгких", userDecision: .accepted),
            SemanticKeyword(text: "КТ лёгких", userDecision: .required),
            SemanticKeyword(text: "ожидающий запрос", userDecision: .pending),
            SemanticKeyword(text: "отклонённый запрос", userDecision: .rejected)
        ]

        let rendered = SemanticPromptRenderer.render(topic: topic)

        #expect(rendered == "МРТ лёгких\nКТ лёгких (обязательный запрос)")
        #expect(!rendered.contains("ожидающий запрос"))
        #expect(!rendered.contains("отклонённый запрос"))
    }

    @Test func fallsBackToLegacySemanticsWhenNoKeywordRecordsExist() {
        let topic = Topic(title: "Тест", articleType: .info)
        topic.semantics = ["старый запрос"]

        #expect(SemanticPromptRenderer.render(topic: topic) == "старый запрос")
    }

    @Test func fallsBackToLegacySemanticsWhenOnlyPendingOrRejectedExist() {
        let topic = Topic(title: "Тест", articleType: .info)
        topic.semantics = ["старый запрос", "второй запрос"]
        topic.semanticKeywords = [
            SemanticKeyword(text: "ожидающий запрос", userDecision: .pending),
            SemanticKeyword(text: "отклонённый запрос", userDecision: .rejected)
        ]

        #expect(SemanticPromptRenderer.render(topic: topic) == "старый запрос\nвторой запрос")
    }
}
