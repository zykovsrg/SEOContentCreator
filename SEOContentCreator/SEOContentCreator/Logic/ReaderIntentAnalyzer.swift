import Foundation

@MainActor
struct ReaderIntentAnalyzer {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = StageExecutor.KeyProvider

    enum AnalyzerError: Error, LocalizedError, Equatable {
        case emptyResponse

        var errorDescription: String? {
            "ИИ не вернул карту задачи читателя. Попробуйте ещё раз."
        }
    }

    let streamProvider: StreamProvider
    let keyProvider: KeyProvider
    let model: String

    static func live(model: String) -> ReaderIntentAnalyzer {
        ReaderIntentAnalyzer(
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

    func analyze(topic: Topic) async throws -> ReaderIntentDraft {
        let key = try keyProvider()
        var collected = ""
        for try await event in streamProvider(
            key,
            ReaderIntentPromptBuilder.systemPrompt,
            ReaderIntentPromptBuilder.userPrompt(topic: topic),
            model,
            0.2,
            2500,
            nil
        ) {
            if case .token(let token) = event { collected += token }
        }
        guard !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyzerError.emptyResponse
        }
        return try ReaderIntentResponseParser.parse(collected)
    }
}
