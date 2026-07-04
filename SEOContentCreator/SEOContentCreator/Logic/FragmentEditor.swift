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
    /// The AI's rewritten fragment (trimmed), nil until a successful run finishes.
    /// The caller (the unified editor) already knows the exact range this
    /// fragment came from, so splicing it back into the full text and
    /// deciding whether/when to persist a new `ArticleVersion` is entirely
    /// the caller's responsibility.
    var rewrittenFragment: String?

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
        fragment: String,
        instruction: String,
        roleKey: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        source: VersionSource,
        topic: Topic,
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastWarningMessage = nil
        rewrittenFragment = nil

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
            var lastFlush = ContinuousClock.now
            for try await event in streamProvider(
                key, prompt.system, prompt.user, model, temperature, maxTokens, nil
            ) {
                switch event {
                case .token(let t):
                    collected += t
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(100) {
                        streamingText = collected
                        lastFlush = now
                    }
                case .finish(reason: let reason):
                    if reason == "length" { truncated = true }
                case .usage(let promptTokens, let completionTokens):
                    job.promptTokens = promptTokens
                    job.completionTokens = completionTokens
                }
            }
            streamingText = collected // final flush after throttling
            if truncated {
                lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
            }

            rewrittenFragment = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            job.status = .success
            job.finishedAt = .now
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
