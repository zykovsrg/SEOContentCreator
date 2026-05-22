import Foundation
import SwiftData

@MainActor
@Observable
final class StageExecutor {
    typealias StreamProvider = (
        _ apiKey: String, _ system: String, _ user: String,
        _ model: String, _ temperature: Double, _ maxTokens: Int
    ) -> AsyncThrowingStream<String, Error>
    typealias KeyProvider = () throws -> String

    var streamingText: String = ""
    var isRunning: Bool = false
    var lastErrorMessage: String?
    /// ID of the version created by the most recent successful run (awaiting accept/reject).
    var lastResultVersionID: UUID?

    private let streamProvider: StreamProvider
    private let keyProvider: KeyProvider

    init(streamProvider: @escaping StreamProvider, keyProvider: @escaping KeyProvider) {
        self.streamProvider = streamProvider
        self.keyProvider = keyProvider
    }

    /// Production convenience: wire to KeychainService + OpenAIClient.
    static func live(model: String) -> StageExecutor {
        StageExecutor(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey, system: system, user: user,
                    model: model, temperature: temperature, maxTokens: maxTokens
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() }
        )
    }

    func execute(
        stage: PipelineStage,
        topic: Topic,
        template: StageTemplate,
        currentText: String?,
        selectedBlocks: [String] = [],
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastResultVersionID = nil

        let job = GenerationJob(stage: stage, agentName: stage.agentName, modelName: template.modelName)
        job.topic = topic
        context.insert(job)

        do {
            let key = try keyProvider()
            let prompt = PromptBuilder().build(
                template: template, topic: topic,
                currentText: currentText, selectedBlocks: selectedBlocks
            )
            var collected = ""
            for try await chunk in streamProvider(
                key, prompt.system, prompt.user,
                template.modelName, template.temperature, template.maxTokens
            ) {
                collected += chunk
                streamingText = collected
            }

            let parsed = StageOutputParser.parse(rawText: collected, stage: stage)
            let version = ArticleVersion(
                stage: stage, source: .generated, text: parsed.body,
                agentName: stage.agentName, templateID: template.uuid, modelName: template.modelName
            )
            version.h1 = parsed.h1
            version.seoTitle = parsed.seoTitle
            version.seoDescription = parsed.seoDescription
            version.topic = topic
            context.insert(version)

            topic.updatedAt = .now

            job.status = .success
            job.finishedAt = .now
            job.resultVersionID = version.uuid
            lastResultVersionID = version.uuid
        } catch {
            job.status = .error
            job.finishedAt = .now
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            job.errorMessage = message
            lastErrorMessage = message
        }

        isRunning = false
    }
}
