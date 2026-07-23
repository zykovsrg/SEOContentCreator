import Foundation

/// Layer 1 of the pipeline: turns a topic into the seed phrases to pull from Wordstat.
@MainActor
struct SemanticSeedPlanner {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = StageExecutor.KeyProvider

    enum PlannerError: Error, LocalizedError, Equatable {
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "Агент не вернул план сбора. Попробуйте ещё раз."
            }
        }
    }

    let streamProvider: StreamProvider
    let keyProvider: KeyProvider
    let model: String

    static func live(model: String) -> SemanticSeedPlanner {
        SemanticSeedPlanner(
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

    func plan(topic: Topic, masks: [String]) async throws -> SemanticSeedPlan {
        let key = try keyProvider()
        var collected = ""

        for try await event in streamProvider(
            key,
            Self.systemPrompt,
            Self.userPrompt(topic: topic, masks: masks),
            model,
            0.3,
            2000,
            nil
        ) {
            if case .token(let token) = event {
                collected += token
            }
        }

        guard !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlannerError.emptyResponse
        }

        return try SemanticSeedPlanParser.parse(collected)
    }

    static let systemPrompt = """
    Ты SEO-аналитик медицинской клиники. Верни только JSON без Markdown.
    Твоя задача — спланировать сбор семантики: какие фразы отправить в Wordstat.
    Не выдумывай вопросительные слова: бери только из предложенного списка.
    """

    static func userPrompt(topic: Topic, masks: [String]) -> String {
        let readerIntent = ReaderIntentPromptRenderer.render(topic: topic)
        return """
        Тема: \(topic.title)
        Тип статьи: \(topic.articleType.title)

        \(readerIntent)

        Используй задачу читателя как рамку для выбора релевантных вариантов темы,
        сокращений, написаний, масок и уточнений. Не выдумывай спрос и частотность.

        Разрешённые вопросительные слова:
        \(masks.joined(separator: ", "))

        Верни JSON:
        {"synonyms":["варианты названия темы: сокращения, разговорные и профессиональные термины, латиница и кириллица"],"masks":["вопросительные слова из списка выше, подходящие теме"],"tails":["уточнения: лечение, цена, симптомы, отзывы, гео — подходящие именно этой теме и задаче читателя"]}
        """
    }
}
