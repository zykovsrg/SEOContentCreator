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
            configurations: config
        )
        return ModelContext(container)
    }

    private func cannedStream(_ chunks: [String]) -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                for c in chunks { continuation.yield(c) }
                continuation.finish()
            }
        }
    }

    @Test func successCreatesCurrentVersionAndSuccessfulJob() async throws {
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
        #expect(topic.currentVersion?.text == "Часть 1 Часть 2")
        #expect(topic.currentVersion?.stageRaw == "draft")
        #expect(topic.jobs.first?.status == .success)
        #expect(executor.lastErrorMessage == nil)
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
}
