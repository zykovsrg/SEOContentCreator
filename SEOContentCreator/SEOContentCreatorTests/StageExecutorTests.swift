import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct StageExecutorTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func cannedStream(_ chunks: [String]) -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                for c in chunks { continuation.yield(.token(c)) }
                continuation.finish()
            }
        }
    }

    @Test func successCreatesPendingVersionNotAutoCurrent() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease,
                          direction: KnowledgeNode(title: "ЛТ", type: .direction))
        context.insert(topic)
        let template = StageTemplate(stage: .draft, systemPrompt: "s", userPromptTemplate: "{{тема}}")
        context.insert(template)

        let executor = StageExecutor(
            streamProvider: cannedStream(["Часть 1 ", "Часть 2"]),
            keyProvider: { "sk-test" }
        )
        await executor.execute(stage: .draft, topic: topic, template: template,
                               currentText: nil, in: context)

        #expect(executor.isRunning == false)
        // Generated version lands in the lane but is NOT auto-current — the user must accept it.
        #expect(topic.currentVersion == nil)
        let created = topic.versions.first { $0.uuid == executor.lastResultVersionID }
        #expect(created?.text == "Часть 1 Часть 2")
        #expect(created?.stageRaw == "draft")
        #expect(created?.source == .generated)
        #expect(topic.jobs.first?.status == .success)
        #expect(executor.lastErrorMessage == nil)
        #expect(executor.lastWarningMessage == nil)
    }

    @Test func missingKeyProducesErrorJobNoVersion() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let template = StageTemplate(stage: .draft, systemPrompt: "s", userPromptTemplate: "x")
        context.insert(template)

        let executor = StageExecutor(
            streamProvider: cannedStream(["ignored"]),
            keyProvider: { throw KeychainService.KeychainError.notFound }
        )
        await executor.execute(stage: .draft, topic: topic, template: template,
                               currentText: nil, in: context)

        #expect(topic.currentVersion == nil)
        #expect(topic.jobs.first?.status == .error)
        #expect(executor.lastErrorMessage == "Укажите API-ключ в Настройках")
    }

    @Test func checkingStagePopulatesRemarksNoVersion() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let template = StageTemplate(stage: .finalReview, systemPrompt: "s", userPromptTemplate: "{{текущий_текст}}")
        context.insert(template)

        let json = #"{"remarks":[{"category":"Орфография","quote":"тест","suggestion":"текст","explanation":"опечатка"}]}"#
        let executor = StageExecutor(streamProvider: cannedStream([json]), keyProvider: { "k" })
        await executor.execute(stage: .finalReview, topic: topic, template: template,
                               currentText: "тест", in: context)

        #expect(executor.remarks.count == 1)
        #expect(executor.remarks.first?.category == "Орфография")
        #expect(topic.currentVersion == nil)         // checking creates no version
        #expect(executor.lastResultVersionID == nil)
        #expect(topic.jobs.first?.status == .success)
    }

    @Test func structureStageGeneratesNoVersion() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease,
                          direction: KnowledgeNode(title: "ЛТ", type: .direction))
        context.insert(topic)
        let template = StageTemplate(stage: .structure, systemPrompt: "s", userPromptTemplate: "{{тема}}")
        context.insert(template)

        let executor = StageExecutor(
            streamProvider: cannedStream(["# H1\n", "## Введение"]),
            keyProvider: { "k" }
        )
        await executor.execute(stage: .structure, topic: topic, template: template,
                               currentText: nil, in: context)

        // Structure generation does not create a version — the plan is persisted into Topic.structureText by the UI.
        #expect(topic.versions.isEmpty)
        #expect(executor.lastResultVersionID == nil)
        #expect(executor.streamingText == "# H1\n## Введение")
        #expect(topic.jobs.first?.status == .success)
        #expect(executor.lastErrorMessage == nil)
    }

    @Test func truncatedStreamSetsWarningAndCreatesVersion() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease,
                          direction: KnowledgeNode(title: "ЛТ", type: .direction))
        context.insert(topic)
        let template = StageTemplate(stage: .draft, systemPrompt: "s", userPromptTemplate: "{{тема}}")
        context.insert(template)

        let provider: StageExecutor.StreamProvider = { _, _, _, _, _, _ in
            AsyncThrowingStream { c in
                c.yield(.token("Обрезанный текст"))
                c.yield(.finish(reason: "length"))
                c.finish()
            }
        }
        let executor = StageExecutor(streamProvider: provider, keyProvider: { "k" })
        await executor.execute(stage: .draft, topic: topic, template: template,
                               currentText: nil, in: context)

        #expect(executor.lastWarningMessage != nil)
        let created = topic.versions.first { $0.uuid == executor.lastResultVersionID }
        #expect(created?.text == "Обрезанный текст")
        #expect(topic.jobs.first?.status == .success)
    }

    @Test func passesRoleContextIntoPromptBuilder() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        context.insert(AIRole(key: "author", name: "Новый автор", mandate: "Мандат роли", blockKeys: ["editorialPolicy"]))
        context.insert(ContextBlock(key: "editorialPolicy", title: "Редполитика", text: "Текст редполитики"))
        let template = StageTemplate(stage: .draft, systemPrompt: "Промт этапа", userPromptTemplate: "{{тема}}")
        context.insert(template)

        var capturedSystem = ""
        let provider: StageExecutor.StreamProvider = { _, system, _, _, _, _ in
            capturedSystem = system
            return AsyncThrowingStream { c in
                c.yield(.token("Текст"))
                c.finish()
            }
        }
        let executor = StageExecutor(streamProvider: provider, keyProvider: { "k" })

        await executor.execute(stage: .draft, topic: topic, template: template,
                               currentText: nil, in: context)

        #expect(capturedSystem == "Мандат роли\n\nТекст редполитики\n\nПромт этапа")
        #expect(topic.jobs.first?.agentName == "Новый автор")
        let created = topic.versions.first { $0.uuid == executor.lastResultVersionID }
        #expect(created?.agentName == "Новый автор")
    }
}
