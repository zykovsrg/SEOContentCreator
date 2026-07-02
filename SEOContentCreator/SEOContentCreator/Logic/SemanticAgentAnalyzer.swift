import Foundation

@MainActor
struct SemanticAgentAnalyzer {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = StageExecutor.KeyProvider

    enum AnalyzerError: Error, LocalizedError, Equatable {
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "Агент не вернул результат. Попробуйте ещё раз."
            }
        }
    }

    let streamProvider: StreamProvider
    let keyProvider: KeyProvider
    let model: String

    static func live(model: String) -> SemanticAgentAnalyzer {
        SemanticAgentAnalyzer(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens, reasoningEffort in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey,
                    system: system,
                    user: user,
                    model: model,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    reasoningEffort: reasoningEffort
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() },
            model: model
        )
    }

    func analyze(topic: Topic, queries: [String], pages: [PublishedSitePage]) async throws -> [SemanticAgentKeywordResult] {
        let key = try keyProvider()
        var collected = ""

        for try await event in streamProvider(
            key,
            systemPrompt,
            userPrompt(topic: topic, queries: queries, pages: pages),
            model,
            0.2,
            4000,
            nil
        ) {
            if case .token(let token) = event {
                collected += token
            }
        }

        guard !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyzerError.emptyResponse
        }

        return try SemanticAgentResponseParser.parse(collected)
    }

    private var systemPrompt: String {
        """
        Ты SEO-аналитик медицинского сайта. Верни только JSON без Markdown.
        Решай, какие запросы стоит включить в семантику темы, а какие не стоит.
        Учитывай мусорные запросы, неподходящий интент и каннибализацию с опубликованными страницами.
        """
    }

    private func userPrompt(topic: Topic, queries: [String], pages: [PublishedSitePage]) -> String {
        """
        Тема: \(topic.title)
        Тип статьи: \(topic.articleType.title)

        Кандидаты:
        \(queries.map { "- \($0)" }.joined(separator: "\n"))

        Опубликованные страницы сайта:
        \(pages.map(\.summaryForAgent).joined(separator: "\n\n---\n\n"))

        Верни JSON:
        {"keywords":[{"query":"...","frequency":null,"recommendation":"include|exclude","reasonCategory":"none|junk|offTopic|cannibalization|lowQuality|tooBroad|wrongIntent|other","explanation":"короткая причина","cannibalizationRisk":"none|low|medium|high","cannibalizationURL":null,"cannibalizationTitle":null}]}
        """
    }
}
