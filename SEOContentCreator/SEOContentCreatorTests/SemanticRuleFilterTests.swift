import Testing
@testable import SEOContentCreator

struct SemanticRuleFilterTests {
    private func phrase(_ text: String, _ frequency: Int) -> WordstatPhrase {
        WordstatPhrase(text: text, frequency: frequency)
    }

    @Test func removesStopWordMatches() {
        let input = [phrase("рак молочной железы реферат", 900), phrase("рак молочной железы лечение", 800)]

        let result = SemanticRuleFilter.apply(input, stopWords: ["реферат"], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["рак молочной железы лечение"])
        #expect(result.dropped.count == 1)
        #expect(result.dropped[0].reason.contains("реферат"))
    }

    @Test func stopWordMatchesWholeWordsOnly() {
        // "тест" must not remove "тестостерон".
        let input = [phrase("тестостерон норма", 500)]

        let result = SemanticRuleFilter.apply(input, stopWords: ["тест"], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["тестостерон норма"])
    }

    @Test func dropsBelowThreshold() {
        let input = [phrase("редкий запрос", 4), phrase("частый запрос", 40)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["частый запрос"])
        #expect(result.dropped[0].reason.contains("частотность"))
    }

    @Test func mergesDuplicatesKeepingHighestFrequency() {
        let input = [phrase("Рак  Груди", 100), phrase("рак груди", 300)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.count == 1)
        #expect(result.survivors[0].frequency == 300)
    }

    @Test func treatsYoAndYeAsSameWord() {
        let input = [phrase("причёска", 50), phrase("прическа", 70)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.count == 1)
    }

    @Test func cutRunsAfterRulesSoLimitIsFilled() {
        // 3 high-frequency academic queries plus 100 usable ones, limit 100.
        var input = [
            phrase("тема реферат", 10_000),
            phrase("тема курсовая", 9_000),
            phrase("тема презентация", 8_000)
        ]
        for index in 0..<100 {
            input.append(phrase("полезный запрос \(index)", 1_000 - index))
        }

        let result = SemanticRuleFilter.apply(input, stopWords: ["реферат", "курсовая", "презентация"], threshold: 10, limit: 100)

        #expect(result.survivors.count == 100)
        #expect(result.survivors.allSatisfy { $0.text.hasPrefix("полезный") })
    }

    @Test func sortsSurvivorsByFrequencyDescending() {
        let input = [phrase("низкий", 20), phrase("высокий", 900), phrase("средний", 100)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["высокий", "средний", "низкий"])
    }

    @Test func recordsPhrasesCutByLimitAsDropped() {
        let input = [phrase("первый", 100), phrase("второй", 50)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 1)

        #expect(result.survivors.map(\.text) == ["первый"])
        #expect(result.dropped.map(\.phrase.text) == ["второй"])
        #expect(result.dropped[0].reason.contains("топ-1"))
    }

    @Test func keepsPhraseExactlyAtThreshold() {
        let input = [phrase("ровно на пороге", 10)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["ровно на пороге"])
        #expect(result.dropped.isEmpty)
    }

    @Test func recordsBlankPhraseAsDropped() {
        let input = [phrase("   ", 500), phrase("нормальный запрос", 500)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["нормальный запрос"])
        #expect(result.dropped.count == 1)
        #expect(result.dropped[0].reason.contains("пустой"))
    }

    @Test func recordsMergedDuplicateAsDropped() {
        let input = [phrase("Рак  Груди", 100), phrase("рак груди", 300)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.count == 1)
        #expect(result.survivors[0].frequency == 300)
        #expect(result.dropped.count == 1)
        #expect(result.dropped[0].phrase.frequency == 100)
        #expect(result.dropped[0].reason.contains("дубликат"))
    }

    @Test func returnsEmptyResultForEmptyInput() {
        let result = SemanticRuleFilter.apply([], stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.isEmpty)
        #expect(result.dropped.isEmpty)
    }

    @Test func limitOfZeroDropsEverything() {
        let input = [phrase("запрос", 500)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 0)

        #expect(result.survivors.isEmpty)
        #expect(result.dropped.count == 1)
    }
}
