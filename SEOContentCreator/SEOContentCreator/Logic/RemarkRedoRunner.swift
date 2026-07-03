import Foundation
import SwiftData

/// Runs a single-remark "redo with comment" call and writes the new
/// `suggestion` back into `executor.remarks` in place. Shared by
/// `TopicWorkspaceView` and `QuickCheckSheet`, which both host a
/// `RemarksPanelView` and a `StageExecutor`.
@MainActor
enum RemarkRedoRunner {
    static func run(
        remark: Remark, comment: String, model: String,
        executor: StageExecutor, topic: Topic?, in context: ModelContext
    ) async {
        let job = GenerationJob(stageLabel: "remarkRedo", agentName: "ИИ-редактор", modelName: model)
        job.topic = topic
        context.insert(job)
        do {
            let key = try KeychainService.loadAPIKey()
            let prompt = RemarkRedoBuilder.build(
                category: remark.category, quote: remark.quote,
                explanation: remark.explanation, comment: comment
            )
            var collected = ""
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
            guard let newSuggestion = RemarkRedoParser.parse(rawText: collected) else {
                job.status = .error
                job.errorMessage = "Не удалось разобрать ответ ИИ."
                job.finishedAt = .now
                executor.lastErrorMessage = "Не удалось разобрать ответ ИИ на доработку замечания."
                return
            }
            if let index = executor.remarks.firstIndex(where: { $0.id == remark.id }) {
                executor.remarks[index].suggestion = newSuggestion
            }
            job.status = .success
            job.finishedAt = .now
        } catch {
            job.status = .error
            job.errorMessage = error.localizedDescription
            job.finishedAt = .now
            executor.lastErrorMessage = error.localizedDescription
        }
    }
}
