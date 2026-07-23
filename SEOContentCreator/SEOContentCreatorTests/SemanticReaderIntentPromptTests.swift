import Testing
@testable import SEOContentCreator

@MainActor
struct SemanticReaderIntentPromptTests {
    private func topicWithIntent() -> Topic {
        let topic = Topic(title: "Манеж для шестимесячного ребёнка", articleType: .info)
        topic.readerIntent = ReaderIntent(
            query: "манеж для 6 месячного",
            audienceContext: "родитель ребёнка шести месяцев",
            hiddenGoal: "обеспечить безопасность и освободить руки",
            successCriterion: "ребёнок в безопасности, родитель может заниматься делами",
            barriers: "страх навредить развитию и ограниченное пространство",
            solutionType: .comparison,
            solutionFormat: "чек-лист критериев выбора",
            coverage: [.choiceComparison, .risksLimitations]
        )
        return topic
    }

    @Test func seedPromptIncludesReaderIntentContext() {
        let prompt = SemanticSeedPlanner.userPrompt(
            topic: topicWithIntent(),
            masks: ["как", "какой"]
        )

        #expect(prompt.contains("Задача читателя:"))
        #expect(prompt.contains("манеж для 6 месячного"))
        #expect(prompt.contains("родитель ребёнка шести месяцев"))
        #expect(prompt.contains("обеспечить безопасность и освободить руки"))
        #expect(prompt.contains("ребёнок в безопасности, родитель может заниматься делами"))
        #expect(prompt.contains("страх навредить развитию"))
        #expect(prompt.contains("- Тип и формат решения: сравнение; чек-лист критериев выбора"))
        #expect(prompt.contains("выбор и сравнение"))
        #expect(prompt.contains("риски и ограничения"))
    }

    @Test func seedPromptKeepsExplicitMissingIntentFallback() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let prompt = SemanticSeedPlanner.userPrompt(topic: topic, masks: ["как"])

        #expect(prompt.contains("Карта задачи читателя не заполнена."))
    }

    @Test func relevancePromptIncludesReaderIntentAndLongTailRule() {
        let prompt = SemanticAgentAnalyzer.userPrompt(
            topic: topicWithIntent(),
            queries: [WordstatPhrase(text: "какой манеж выбрать", frequency: 120)]
        )

        #expect(prompt.contains("Задача читателя:"))
        #expect(prompt.contains("манеж для 6 месячного"))
        #expect(prompt.contains("родитель ребёнка шести месяцев"))
        #expect(prompt.contains("обеспечить безопасность и освободить руки"))
        #expect(prompt.contains("ребёнок в безопасности, родитель может заниматься делами"))
        #expect(prompt.contains("страх навредить развитию и ограниченное пространство"))
        #expect(prompt.contains("- Тип и формат решения: сравнение; чек-лист критериев выбора"))
        #expect(prompt.contains("выбор и сравнение"))
        #expect(prompt.contains("риски и ограничения"))
        #expect(prompt.contains("какой манеж выбрать — 120"))
        #expect(prompt.contains("10 длинных запросов из 3-7 слов"))
    }

    @Test func relevancePromptKeepsExplicitMissingIntentFallback() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let prompt = SemanticAgentAnalyzer.userPrompt(
            topic: topic,
            queries: [WordstatPhrase(text: "лечение рака простаты", frequency: 300)]
        )

        #expect(prompt.contains("Карта задачи читателя не заполнена."))
    }

    @Test func relevanceSystemPromptKeepsAcademicAndWrongIntentRules() {
        #expect(SemanticAgentAnalyzer.systemPrompt.contains("академические"))
        #expect(SemanticAgentAnalyzer.systemPrompt.contains("интент"))
        #expect(SemanticAgentAnalyzer.systemPrompt.contains("типом статьи"))
    }
}
