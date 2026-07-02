import Testing
@testable import SEOContentCreator

struct SemanticKeywordMergerTests {
    @Test func savesAgentResultsAsPendingDecisions() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let result = SemanticAgentKeywordResult(
            query: "рак простаты лечение",
            frequency: 120,
            recommendation: .include,
            reasonCategory: .none,
            explanation: "Подходит теме",
            cannibalizationRisk: .none,
            cannibalizationURL: nil,
            cannibalizationTitle: nil
        )

        SemanticKeywordMerger.merge([result], into: topic)

        #expect(topic.semanticKeywords.count == 1)
        #expect(topic.semanticKeywords[0].userDecision == .pending)
        #expect(topic.semanticKeywords[0].agentRecommendation == .include)
        #expect(topic.semanticKeywords[0].frequency == 120)
    }

    @Test func updatesExistingKeywordInsteadOfDuplicating() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let existing = SemanticKeyword(text: "рак простаты лечение", userDecision: .accepted)
        existing.topic = topic
        topic.semanticKeywords = [existing]
        let result = SemanticAgentKeywordResult(
            query: " Рак Простаты Лечение ",
            frequency: 200,
            recommendation: .exclude,
            reasonCategory: .cannibalization,
            explanation: "Есть похожая страница",
            cannibalizationRisk: .high,
            cannibalizationURL: "https://hadassah.moscow/prostate",
            cannibalizationTitle: "Рак простаты"
        )

        SemanticKeywordMerger.merge([result], into: topic)

        #expect(topic.semanticKeywords.count == 1)
        #expect(topic.semanticKeywords[0].userDecision == .accepted)
        #expect(topic.semanticKeywords[0].agentRecommendation == .exclude)
        #expect(topic.semanticKeywords[0].frequency == 200)
        #expect(topic.semanticKeywords[0].reasonCategory == .cannibalization)
        #expect(topic.semanticKeywords[0].cannibalizationRisk == .high)
        #expect(topic.semanticKeywords[0].cannibalizationURL == "https://hadassah.moscow/prostate")
        #expect(topic.semanticKeywords[0].cannibalizationTitle == "Рак простаты")
    }
}
