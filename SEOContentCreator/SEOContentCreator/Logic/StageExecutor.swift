import Foundation
import SwiftData

@MainActor
@Observable
final class StageExecutor {
    typealias StreamProvider = (
        _ apiKey: String, _ system: String, _ user: String,
        _ model: String, _ temperature: Double, _ maxTokens: Int
    ) -> AsyncThrowingStream<OpenAIStreamEvent, Error>
    typealias KeyProvider = () throws -> String

    var streamingText: String = ""
    var isRunning: Bool = false
    var lastErrorMessage: String?
    /// Transient warning from the most recent run (e.g., output truncated by token limit). Not persisted.
    var lastWarningMessage: String?
    /// ID of the version created by the most recent successful run (awaiting accept/reject).
    var lastResultVersionID: UUID?
    /// Transient remarks from the most recent checking run (not persisted).
    var remarks: [Remark] = []

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
        lastWarningMessage = nil
        lastResultVersionID = nil
        remarks = []

        let role = fetchRole(for: stage, in: context)
        let agentName = role?.name ?? stage.agentName
        let job = GenerationJob(stage: stage, agentName: agentName, modelName: template.modelName)
        job.topic = topic
        context.insert(job)

        do {
            let key = try keyProvider()
            let roleContext = buildRoleContext(for: role, in: context)
            let prompt = PromptBuilder().build(
                template: template, topic: topic,
                currentText: currentText, selectedBlocks: selectedBlocks,
                roleContext: roleContext
            )
            var collected = ""
            var truncated = false
            for try await event in streamProvider(
                key, prompt.system, prompt.user,
                template.modelName, template.temperature, template.maxTokens
            ) {
                switch event {
                case .token(let t):
                    collected += t
                    streamingText = collected
                case .finish(let reason):
                    if reason == "length" { truncated = true }
                }
            }
            if truncated {
                lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
            }

            if stage.kind == .checking {
                remarks = RemarksParser.parse(rawText: collected)
                job.status = .success
                job.finishedAt = .now
            } else {
                let parsed = StageOutputParser.parse(rawText: collected, stage: stage)
                let version = ArticleVersion(
                    stage: stage, source: .generated, text: parsed.body,
                    agentName: agentName, templateID: template.uuid, modelName: template.modelName
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
            }
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

    private func fetchRole(for stage: PipelineStage, in context: ModelContext) -> AIRole? {
        let roleKey = stage.roleKey
        let roleDescriptor = FetchDescriptor<AIRole>(
            predicate: #Predicate { $0.key == roleKey }
        )
        return (try? context.fetch(roleDescriptor))?.first
    }

    private func buildRoleContext(for role: AIRole?, in context: ModelContext) -> String {
        guard let role else { return "" }
        let blocks = (try? context.fetch(FetchDescriptor<ContextBlock>())) ?? []
        return RoleContextAssembler.assemble(role: role, blocks: blocks)
    }
}
