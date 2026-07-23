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

    func analyze(topic: Topic, queries: [WordstatPhrase]) async throws -> SemanticAgentAnalysis {
        let key = try keyProvider()
        var collected = ""

        for try await event in streamProvider(
            key,
            Self.systemPrompt,
            Self.userPrompt(topic: topic, queries: queries),
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

    static let systemPrompt = """
        Ты SEO-аналитик медицинского сайта. Верни только JSON без Markdown.
        Решай, какие запросы стоит включить в семантику темы, а какие не стоит.
        Сгруппируй близкие по смыслу запросы самостоятельно, без стороннего сервиса:
        убери дубли и оставь наиболее естественные формулировки из каждого кластера.
        Отклоняй академические и учебные формулировки, а также запросы,
        интент которых не совпадает с типом статьи.
        """

    static func userPrompt(topic: Topic, queries: [WordstatPhrase]) -> String {
        let readerIntent = ReaderIntentPromptRenderer.render(topic: topic)
        return """
        Тема: \(topic.title)
        Тип статьи: \(topic.articleType.title)

        \(readerIntent)

        Оценивай релевантность не только названию темы, но и целевой аудитории,
        практической задаче, критерию успеха и барьерам из карты. Карта — контекст:
        не выдумывай спрос, медицинские факты или обещания и не эксплуатируй страхи.

        Кандидаты (запрос — частотность):
        \(queries.map { "- \($0.text) — \($0.frequency)" }.joined(separator: "\n"))

        Дополнительно составь 10 длинных запросов из 3-7 слов, которые, по твоему
        мнению, интересны целевой аудитории, и верни их в поле longTail.

        Верни JSON:
        {"keywords":[{"query":"...","recommendation":"include|exclude","reasonCategory":"none|junk|offTopic|lowQuality|tooBroad|wrongIntent|other","explanation":"короткая причина"}],"longTail":["..."]}
        """
    }
}
