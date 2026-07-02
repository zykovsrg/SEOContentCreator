import Testing
@testable import SEOContentCreator

struct SemanticKeywordBackfillTests {
    @Test func backfillsLegacySemanticsAsAcceptedKeywords() throws {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        topic.semantics = ["рак простаты лечение", "лучевая терапия простаты"]

        SemanticKeywordBackfill.backfill(topic)

        #expect(topic.semanticKeywords.count == 2)
        #expect(topic.semanticKeywords.map(\.text).contains("рак простаты лечение"))
        #expect(topic.semanticKeywords.allSatisfy { $0.userDecision == .accepted })
        #expect(topic.semanticKeywords.allSatisfy { $0.agentRecommendation == .none })
        #expect(topic.semantics == ["рак простаты лечение", "лучевая терапия простаты"])
    }

    @Test func backfillDoesNotDuplicateExistingKeyword() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        topic.semantics = ["рак простаты лечение"]
        let existing = SemanticKeyword(text: "рак простаты лечение", userDecision: .accepted)
        existing.topic = topic
        topic.semanticKeywords = [existing]

        SemanticKeywordBackfill.backfill(topic)

        #expect(topic.semanticKeywords.count == 1)
    }

    @Test func backfillDoesNotDuplicateRepeatedLegacyStrings() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        topic.semantics = ["рак простаты лечение", "рак простаты лечение"]

        SemanticKeywordBackfill.backfill(topic)

        #expect(topic.semanticKeywords.count == 1)
    }

    @Test func backfillDeduplicatesWhitespaceAndCaseVariants() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        topic.semantics = ["  РАК ПРОСТАТЫ ЛЕЧЕНИЕ  ", "рак простаты лечение", "\nРак Простаты Лечение\t"]

        SemanticKeywordBackfill.backfill(topic)

        #expect(topic.semanticKeywords.count == 1)
        #expect(topic.semanticKeywords.first?.text == "РАК ПРОСТАТЫ ЛЕЧЕНИЕ")
    }

    @Test func backfillIgnoresWhitespaceOnlyLegacyStrings() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        topic.semantics = ["   ", "\n\t", " рак простаты лечение "]

        SemanticKeywordBackfill.backfill(topic)

        #expect(topic.semanticKeywords.count == 1)
        #expect(topic.semanticKeywords.first?.text == "рак простаты лечение")
    }

    @Test func backfillIsIdempotent() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        topic.semantics = [" рак простаты лечение "]

        SemanticKeywordBackfill.backfill(topic)
        SemanticKeywordBackfill.backfill(topic)

        #expect(topic.semanticKeywords.count == 1)
        #expect(topic.semanticKeywords.first?.text == "рак простаты лечение")
    }
}
