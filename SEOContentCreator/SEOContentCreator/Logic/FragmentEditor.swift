import Foundation
import SwiftData

@MainActor
@Observable
final class FragmentEditor {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = () throws -> String

    var streamingText: String = ""
    var isRunning: Bool = false
    var lastErrorMessage: String?
    var lastWarningMessage: String?
    /// Spliced full text awaiting accept/reject; nil until a successful run.
    var proposedText: String?

    private(set) var proposedSource: VersionSource = .skillApplied
    private(set) var agentName: String?

    private let streamProvider: StreamProvider
    private let keyProvider: KeyProvider

    init(streamProvider: @escaping StreamProvider, keyProvider: @escaping KeyProvider) {
        self.streamProvider = streamProvider
        self.keyProvider = keyProvider
    }

    static func live() -> FragmentEditor {
        FragmentEditor(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens, reasoningEffort in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey, system: system, user: user,
                    model: model, temperature: temperature, maxTokens: maxTokens,
                    reasoningEffort: reasoningEffort
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() }
        )
    }

    func run(
        fullText: String,
        fragment: String,
        instruction: String,
        source: VersionSource,
        roleKey: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        topic: Topic,
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastWarningMessage = nil
        proposedText = nil
        proposedSource = source

        let role = fetchRole(roleKey, in: context)
        let name = role?.name ?? "ИИ"
        agentName = name
        let job = GenerationJob(stageLabel: source.rawValue, agentName: name, modelName: model)
        job.topic = topic
        context.insert(job)

        do {
            let key = try keyProvider()
            let roleContext = buildRoleContext(role, in: context)
            let prompt = FragmentPromptBuilder().build(
                roleContext: roleContext, instruction: instruction, fragment: fragment
            )
            var collected = ""
            var truncated = false
            for try await event in streamProvider(
                key, prompt.system, prompt.user, model, temperature, maxTokens, nil
            ) {
                switch event {
                case .token(let t):
                    collected += t
                    streamingText = collected
                case .finish(reason: let reason):
                    if reason == "length" { truncated = true }
                }
            }
            if truncated {
                lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
            }

            let rewritten = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            switch FragmentSplicer.splice(fullText: fullText, fragment: fragment, replacement: rewritten) {
            case .replaced(let newText):
                proposedText = newText
                job.status = .success
                job.finishedAt = .now
            case .notFound:
                lastErrorMessage = "Фрагмент не найден в тексте — проверьте, что скопировали его точно."
                job.status = .error
                job.finishedAt = .now
            case .ambiguous(let count):
                lastErrorMessage = "Фрагмент встречается \(count) раз — расширьте выделение, чтобы он был уникальным."
                job.status = .error
                job.finishedAt = .now
            }
        } catch {
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            job.errorMessage = message
            job.status = .error
            job.finishedAt = .now
            lastErrorMessage = message
        }

        isRunning = false
    }

    func accept(topic: Topic, in context: ModelContext) {
        guard let text = proposedText else { return }
        let version = ArticleVersion(
            stageLabel: proposedSource.rawValue, source: proposedSource,
            text: text, agentName: agentName
        )
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
        proposedText = nil
    }

    private func fetchRole(_ key: String, in context: ModelContext) -> AIRole? {
        let descriptor = FetchDescriptor<AIRole>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor))?.first
    }

    private func buildRoleContext(_ role: AIRole?, in context: ModelContext) -> String {
        guard let role else { return "" }
        let blocks = (try? context.fetch(FetchDescriptor<ContextBlock>())) ?? []
        return RoleContextAssembler.assemble(role: role, blocks: blocks)
    }
}
