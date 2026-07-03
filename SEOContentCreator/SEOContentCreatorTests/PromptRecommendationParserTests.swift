import Testing
@testable import SEOContentCreator

struct PromptRecommendationParserTests {
    @Test func parsesRecommendationsFromFencedJSON() {
        let raw = """
        Вот рекомендации:
        ```json
        {"recommendations":[{"problem":"Повторяющиеся канцеляризмы","location":"Черновик","suggestion":"Добавить в промт запрет на канцелярит"}]}
        ```
        """
        let recommendations = PromptRecommendationParser.parse(rawText: raw)
        #expect(recommendations.count == 1)
        #expect(recommendations.first?.problem == "Повторяющиеся канцеляризмы")
        #expect(recommendations.first?.location == "Черновик")
        #expect(recommendations.first?.suggestion == "Добавить в промт запрет на канцелярит")
    }

    @Test func parsesRawJSONObject() {
        let raw = #"{"recommendations":[{"problem":"P","location":"L","suggestion":"S"}]}"#
        let recommendations = PromptRecommendationParser.parse(rawText: raw)
        #expect(recommendations.count == 1)
    }

    @Test func brokenOrEmptyReturnsEmpty() {
        #expect(PromptRecommendationParser.parse(rawText: "нет json").isEmpty)
        #expect(PromptRecommendationParser.parse(rawText: "").isEmpty)
        #expect(PromptRecommendationParser.parse(rawText: #"{"recommendations": "не массив"}"#).isEmpty)
    }

    @Test func parsesMultipleRecommendations() {
        let raw = #"{"recommendations":[{"problem":"A","location":"L1","suggestion":"S1"},{"problem":"B","location":"L2","suggestion":"S2"}]}"#
        let recommendations = PromptRecommendationParser.parse(rawText: raw)
        #expect(recommendations.count == 2)
        #expect(recommendations[0].problem == "A")
        #expect(recommendations[1].problem == "B")
    }
}
