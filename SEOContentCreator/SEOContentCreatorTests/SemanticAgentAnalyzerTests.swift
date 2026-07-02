import Testing
@testable import SEOContentCreator

@MainActor
struct SemanticAgentAnalyzerTests {
    @Test func sendsTopicQueriesAndPagesToStreamProvider() async throws {
        var capturedUser = ""
        let analyzer = SemanticAgentAnalyzer(
            streamProvider: { _, _, user, _, _, _, _ in
                capturedUser = user
                return AsyncThrowingStream { continuation in
                    continuation.yield(.token("""
                    {"keywords":[{"query":"рак простаты лечение","frequency":10,"recommendation":"include","reasonCategory":"none","explanation":"Подходит теме","cannibalizationRisk":"none"}]}
                    """))
                    continuation.finish()
                }
            },
            keyProvider: { "sk-test" },
            model: "gpt-4.1"
        )
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let page = PublishedSitePage(url: "https://hadassah.moscow/prostate", title: "Рак простаты")

        let result = try await analyzer.analyze(
            topic: topic,
            queries: ["рак простаты лечение"],
            pages: [page]
        )

        #expect(result.count == 1)
        #expect(capturedUser.contains("Рак простаты"))
        #expect(capturedUser.contains("рак простаты лечение"))
        #expect(capturedUser.contains("https://hadassah.moscow/prostate"))
    }

    @Test func rejectsEmptyStreamResponse() async {
        let analyzer = SemanticAgentAnalyzer(
            streamProvider: { _, _, _, _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            },
            keyProvider: { "sk-test" },
            model: "gpt-4.1"
        )
        let topic = Topic(title: "Рак простаты", articleType: .disease)

        await #expect(throws: SemanticAgentAnalyzer.AnalyzerError.emptyResponse) {
            try await analyzer.analyze(topic: topic, queries: ["рак простаты лечение"], pages: [])
        }
    }
}
