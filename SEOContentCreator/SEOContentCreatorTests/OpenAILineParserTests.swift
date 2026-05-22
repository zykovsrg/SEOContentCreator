import Testing
@testable import SEOContentCreator

struct OpenAILineParserTests {
    @Test func parsesContentToken() {
        let line = #"data: {"choices":[{"delta":{"content":"Привет"}}]}"#
        #expect(OpenAILineParser.parse(line: line) == .token("Привет"))
    }

    @Test func recognisesDone() {
        #expect(OpenAILineParser.parse(line: "data: [DONE]") == .done)
    }

    @Test func ignoresEmptyAndNonData() {
        #expect(OpenAILineParser.parse(line: "") == .ignore)
        #expect(OpenAILineParser.parse(line: ": keep-alive") == .ignore)
    }

    @Test func ignoresDeltaWithoutContent() {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        #expect(OpenAILineParser.parse(line: line) == .ignore)
    }
}
