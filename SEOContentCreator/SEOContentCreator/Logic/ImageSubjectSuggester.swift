import Foundation
import SwiftData

/// Builds the prompt asking the model to distill a concrete visual subject
/// (what should be depicted) from the article/topic context. Reuses the
/// existing per-kind `ImagePromptTemplate` as authoring guidance, rather than
/// as the final image prompt (FT-20260703-004).
enum ImageSubjectPromptBuilder {
    static func build(template: ImagePromptTemplate, topic: Topic, fragment: String) -> (system: String, user: String) {
        let system = """
        Ты помогаешь сформулировать краткое описание сюжета (subject) для генерации изображения.
        Дай только 1–2 предложения с описанием, что должно быть на картинке — без указаний на стиль, свет, ракурс или композицию.
        Отвечай только текстом описания, без пояснений и кавычек.
        """
        let instruction = ImagePromptBuilder().subject(template: template, topic: topic, fragment: fragment)
        return (system, instruction)
    }
}

/// Runs a short, non-streamed-to-UI completion to auto-fill the `subject`
/// field before the user edits it. Mirrors `RemarkRedoRunner`'s pattern of a
/// standalone OpenAIClient call with its own `GenerationJob` for token tracking.
enum ImageSubjectSuggester {
    static func suggest(
        template: ImagePromptTemplate, topic: Topic, fragment: String, model: String, in context: ModelContext
    ) async throws -> String {
        let job = GenerationJob(stageLabel: "imageSubject", agentName: "Генератор изображений", modelName: model)
        job.topic = topic
        context.insert(job)

        let key = try KeychainService.loadAPIKey()
        let prompt = ImageSubjectPromptBuilder.build(template: template, topic: topic, fragment: fragment)
        var collected = ""
        do {
            for try await event in OpenAIClient().streamCompletion(
                apiKey: key, system: prompt.system, user: prompt.user, model: model
            ) {
                switch event {
                case .token(let t): collected += t
                case .usage(let promptTokens, let completionTokens):
                    job.promptTokens = promptTokens
                    job.completionTokens = completionTokens
                case .finish: break
                }
            }
            job.status = .success
            job.finishedAt = .now
        } catch {
            job.status = .error
            job.errorMessage = error.localizedDescription
            job.finishedAt = .now
            throw error
        }
        return collected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
