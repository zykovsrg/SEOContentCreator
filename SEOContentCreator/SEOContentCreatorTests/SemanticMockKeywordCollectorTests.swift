import Testing
@testable import SEOContentCreator

struct SemanticMockKeywordCollectorTests {
    @Test func returnsStableQueriesForTopic() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)

        let first = SemanticMockKeywordCollector.collect(for: topic)
        let second = SemanticMockKeywordCollector.collect(for: topic)

        #expect(first == second)
        #expect(first.contains("рак простаты лечение"))
        #expect(first.contains("рак простаты цена"))
    }

    @Test func usesNormalizedTitleForDeterministicQueries() {
        let topic = Topic(title: "  Рак Простаты  ", articleType: .disease)

        let queries = SemanticMockKeywordCollector.collect(for: topic)

        #expect(queries.first == "рак простаты лечение")
        #expect(Set(queries).count == queries.count)
    }

    @Test func returnsEmptyListForBlankTitle() {
        let topic = Topic(title: "   ", articleType: .disease)

        let queries = SemanticMockKeywordCollector.collect(for: topic)

        #expect(queries.isEmpty)
    }

    @Test func returnsServiceSpecificQueriesWithoutDuplicates() {
        let topic = Topic(title: "КТ", articleType: .service)

        let queries = SemanticMockKeywordCollector.collect(for: topic)

        #expect(queries.contains("кт стоимость"))
        #expect(queries.contains("кт запись"))
        #expect(Set(queries).count == queries.count)
    }

    @Test func returnsInfoSpecificQueriesWithoutDuplicates() {
        let topic = Topic(title: "Иммунотерапия", articleType: .info)

        let queries = SemanticMockKeywordCollector.collect(for: topic)

        #expect(queries.contains("иммунотерапия что это"))
        #expect(queries.contains("иммунотерапия профилактика"))
        #expect(Set(queries).count == queries.count)
    }
}
