import Foundation
import SwiftData
import os

/// TEMP diagnostics for the "generation slows down as text grows" investigation
/// (see ai/current-task.md). Logs when a token event actually reaches MainActor — compare
/// against `networkPerfLog` in OpenAIClient to see whether MainActor is falling behind the
/// network's own pacing. Remove once the root cause is confirmed and fixed.
let mainActorPerfLog = Logger(subsystem: "com.zykovsrg.SEOContentCreator", category: "streaming-perf-mainactor")

@MainActor
@Observable
final class StageExecutor {
    typealias StreamProvider = (
        _ apiKey: String, _ system: String, _ user: String,
        _ model: String, _ temperature: Double, _ maxTokens: Int,
        _ reasoningEffort: String?
    ) -> AsyncThrowingStream<OpenAIStreamEvent, Error>
    typealias KeyProvider = () throws -> String

    var streamingText: String = ""
    var isRunning: Bool = false
    var lastErrorMessage: String?
    /// Transient warning from the most recent run (e.g., output truncated by token limit). Not persisted.
    var lastWarningMessage: String?
    /// ID of the version created by the most recent successful run (awaiting accept/reject).
    var lastResultVersionID: UUID?
    /// Transient remarks from the most recent checking run (durably backed by
    /// `PersistedRemark` records on `lastRemarksJobID`'s job, see FT-20260702-011).
    var remarks: [Remark] = []
    /// The `GenerationJob` whose `PersistedRemark`s back the current `remarks`,
    /// so the UI can update/resolve them as the user reviews.
    var lastRemarksJobID: UUID?

    private let streamProvider: StreamProvider
    private let keyProvider: KeyProvider
    /// The in-flight `execute(...)` run, if any. Lets `cancel()` stop a run started
    /// from a plain `Task { await executor.execute(...) }` at the call site.
    private var currentTask: Task<Void, Never>?

    init(streamProvider: @escaping StreamProvider, keyProvider: @escaping KeyProvider) {
        self.streamProvider = streamProvider
        self.keyProvider = keyProvider
    }

    /// Cancels the run started by `execute(...)`, if one is in flight.
    /// The stream stops and the job is marked `.cancelled` instead of being left `.running`.
    func cancel() {
        currentTask?.cancel()
    }

    /// Production convenience: wire to KeychainService + OpenAIClient.
    static func live(model: String) -> StageExecutor {
        StageExecutor(
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

    func execute(
        stage: PipelineStage,
        topic: Topic,
        template: StageTemplate,
        currentText: String?,
        selectedBlocks: [String] = [],
        modelName: String? = nil,
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastWarningMessage = nil
        lastResultVersionID = nil
        remarks = []
        lastRemarksJobID = nil

        let role = fetchRole(for: stage, in: context)
        let agentName = role?.name ?? stage.agentName
        let runtimeModel = modelName ?? template.modelName
        let job = GenerationJob(stage: stage, agentName: agentName, modelName: runtimeModel)
        job.topic = topic
        context.insert(job)

        let task = Task { [self] in
            do {
                let key = try keyProvider()
                let roleContext = buildRoleContext(for: role, in: context)
                let stageTemplatesSummary = stage == .promptAnalysis ? fetchStageTemplatesSummary(in: context) : ""
                let prompt = PromptBuilder().build(
                    template: template, topic: topic,
                    currentText: currentText, selectedBlocks: selectedBlocks,
                    roleContext: roleContext,
                    forbiddenPhrases: fetchForbiddenPhrases(in: context),
                    stageTemplatesSummary: stageTemplatesSummary
                )
                var collected = ""
                var truncated = false
                var lastFlush = ContinuousClock.now
                var mainTokenCount = 0
                let mainStart = ContinuousClock.now
                var mainLastLog = mainStart
                for try await event in streamProvider(
                    key, prompt.system, prompt.user,
                    runtimeModel, template.temperature, template.maxTokens,
                    template.reasoningEffort
                ) {
                    try Task.checkCancellation()
                    switch event {
                    case .token(let t):
                        collected += t
                        mainTokenCount += 1
                        if mainTokenCount % 50 == 0 {
                            let n = ContinuousClock.now
                            mainActorPerfLog.debug("main tokens=\(mainTokenCount) chars=\(collected.count) sinceStart=\(n - mainStart, privacy: .public) sinceLast50=\(n - mainLastLog, privacy: .public)")
                            mainLastLog = n
                        }
                        // Coalesce UI updates: reassigning streamingText on every token forces
                        // SwiftUI to re-lay-out the ever-growing stream text hundreds of times a
                        // second, and each layout costs more as the text grows (O(n²) overall).
                        // Publishing ~10x/sec keeps streaming smooth without the quadratic blowup.
                        let now = ContinuousClock.now
                        if now - lastFlush >= .milliseconds(100) {
                            streamingText = collected
                            lastFlush = now
                        }
                    case .finish(let reason):
                        if reason == "length" { truncated = true }
                    case .usage(let promptTokens, let completionTokens):
                        job.promptTokens = promptTokens
                        job.completionTokens = completionTokens
                    }
                }
                try Task.checkCancellation()
                // Final flush: throttling may have skipped the last tokens, and `.structure`
                // persists the plan straight from streamingText — it must be complete.
                streamingText = collected
                if truncated {
                    lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
                }

                if stage == .structure {
                    // Plan stays in streamingText; the caller persists it into Topic.structureText. No version is created.
                    job.status = .success
                    job.finishedAt = .now
                } else if stage.kind == .checking {
                    remarks = RemarksParser.parse(rawText: collected)
                    lastRemarksJobID = job.uuid
                    RemarkPersistence.persist(remarks: remarks, job: job, in: context)
                    job.status = .success
                    job.finishedAt = .now
                } else if stage == .promptAnalysis {
                    for recommendation in PromptRecommendationParser.parse(rawText: collected) {
                        let saved = PromptRecommendation(
                            problem: recommendation.problem,
                            location: recommendation.location,
                            suggestion: recommendation.suggestion
                        )
                        saved.topic = topic
                        saved.job = job
                        context.insert(saved)
                    }
                    job.status = .success
                    job.finishedAt = .now
                } else {
                    let parsed = StageOutputParser.parse(rawText: collected, stage: stage)
                    let version = ArticleVersion(
                        stage: stage, source: .generated, text: parsed.body,
                        agentName: agentName, templateID: template.uuid, modelName: runtimeModel
                    )
                    version.h1 = parsed.h1
                    version.seoTitle = parsed.seoTitle
                    version.seoDescription = parsed.seoDescription
                    version.status = .pending
                    version.topic = topic
                    context.insert(version)

                    topic.updatedAt = .now

                    job.status = .success
                    job.finishedAt = .now
                    job.resultVersionID = version.uuid
                    lastResultVersionID = version.uuid
                }
            } catch is CancellationError {
                job.status = .cancelled
                job.finishedAt = .now
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
        }
        currentTask = task
        await task.value
        currentTask = nil

        isRunning = false
    }

    /// Runs a stage template against an existing topic without persisting anything.
    /// Intended for the stage prompt sandbox in Templates.
    func executeSandbox(
        stage: PipelineStage,
        topic: Topic,
        template: StageTemplate,
        currentText: String?,
        selectedBlocks: [String] = [],
        modelName: String? = nil,
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastWarningMessage = nil
        lastResultVersionID = nil
        remarks = []

        let role = fetchRole(for: stage, in: context)
        let runtimeModel = modelName ?? template.modelName
        do {
            let key = try keyProvider()
            let roleContext = buildRoleContext(for: role, in: context)
            let prompt = PromptBuilder().build(
                template: template,
                topic: topic,
                currentText: currentText,
                selectedBlocks: selectedBlocks,
                roleContext: roleContext,
                forbiddenPhrases: fetchForbiddenPhrases(in: context)
            )
            var collected = ""
            var truncated = false
            var lastFlush = ContinuousClock.now
            for try await event in streamProvider(
                key,
                prompt.system,
                prompt.user,
                runtimeModel,
                template.temperature,
                template.maxTokens,
                template.reasoningEffort
            ) {
                switch event {
                case .token(let t):
                    collected += t
                    // See execute(): coalesce UI updates to avoid O(n²) re-layout of the stream.
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(100) {
                        streamingText = collected
                        lastFlush = now
                    }
                case .finish(let reason):
                    if reason == "length" { truncated = true }
                case .usage:
                    break // no GenerationJob in the sandbox run to persist usage against
                }
            }
            streamingText = collected // final flush after throttling
            if truncated {
                lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
            }
            if stage.kind == .checking {
                remarks = RemarksParser.parse(rawText: collected)
            }
        } catch {
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            lastErrorMessage = message
        }

        isRunning = false
    }

    /// Runs a single checking stage on arbitrary pasted text, without persisting
    /// anything (no GenerationJob, no ArticleVersion, no Topic). Fills `remarks`.
    /// Intended for the topic-less "Быстрая проверка" sheet.
    func executeQuickCheck(
        stage: PipelineStage,
        pastedText: String,
        template: StageTemplate,
        modelName: String? = nil,
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastWarningMessage = nil
        lastResultVersionID = nil
        remarks = []

        let role = fetchRole(for: stage, in: context)
        let runtimeModel = modelName ?? template.modelName
        do {
            let key = try keyProvider()
            let roleContext = buildRoleContext(for: role, in: context)
            // Transient, NOT inserted into the context: only carries the pasted text.
            let scratch = Topic(title: "", articleType: .info)
            let prompt = PromptBuilder().build(
                template: template, topic: scratch,
                currentText: pastedText, selectedBlocks: [],
                roleContext: roleContext,
                forbiddenPhrases: fetchForbiddenPhrases(in: context)
            )
            var collected = ""
            var truncated = false
            var lastFlush = ContinuousClock.now
            for try await event in streamProvider(
                key, prompt.system, prompt.user,
                runtimeModel, template.temperature, template.maxTokens,
                template.reasoningEffort
            ) {
                switch event {
                case .token(let t):
                    collected += t
                    // See execute(): coalesce UI updates to avoid O(n²) re-layout of the stream.
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(100) {
                        streamingText = collected
                        lastFlush = now
                    }
                case .finish(let reason):
                    if reason == "length" { truncated = true }
                case .usage:
                    break // no GenerationJob in quick check to persist usage against
                }
            }
            streamingText = collected // final flush after throttling
            if truncated {
                lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
            }
            remarks = RemarksParser.parse(rawText: collected)
        } catch {
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
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

    private func fetchForbiddenPhrases(in context: ModelContext) -> String {
        let phrases = (try? context.fetch(FetchDescriptor<ForbiddenPhrase>())) ?? []
        return ForbiddenPhraseRenderer.render(phrases)
    }

    /// Renders every non-action, non-analysis stage's current system+user prompt,
    /// for the `.promptAnalysis` stage's `{{текущие_промты_этапов}}` placeholder.
    private func fetchStageTemplatesSummary(in context: ModelContext) -> String {
        let templates = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
        let relevantStages = PipelineStage.allCases.filter { $0.kind != .action && $0.kind != .analysis }
        return relevantStages.compactMap { stage -> String? in
            guard let template = templates.first(where: { $0.stageRaw == stage.rawValue }) else { return nil }
            return "## \(stage.title)\nUser:\n\(template.userPromptTemplate)"
        }.joined(separator: "\n\n")
    }
}
