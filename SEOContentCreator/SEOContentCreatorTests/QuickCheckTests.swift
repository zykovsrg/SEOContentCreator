import Testing
import SwiftData
import Foundation
@testable import SEOContentCreator

@MainActor
struct QuickCheckExecutorTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, ArticleVersion.self, GenerationJob.self,
            AIRole.self, ContextBlock.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func tokenStream(_ text: String) -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.token(text))
                continuation.yield(.finish(reason: "stop"))
                continuation.finish()
            }
        }
    }

    private let remarkJSON = """
    {"remarks":[{"category":"SEO","quote":"плохо","suggestion":"хорошо","explanation":"так лучше"}]}
    """

    @Test func parsesRemarksFromResponse() async throws {
        let context = try makeContext()
        let executor = StageExecutor(streamProvider: tokenStream(remarkJSON), keyProvider: { "key" })
        let template = StageTemplate(stage: .seoCheck, systemPrompt: "sys", userPromptTemplate: "Проверь: {{текущий_текст}}")

        await executor.executeQuickCheck(stage: .seoCheck, pastedText: "плохо текст", template: template, in: context)

        #expect(executor.remarks.count == 1)
        #expect(executor.remarks.first?.suggestion == "хорошо")
        #expect(executor.lastErrorMessage == nil)
    }

    @Test func doesNotPersistJobOrVersion() async throws {
        let context = try makeContext()
        let executor = StageExecutor(streamProvider: tokenStream(remarkJSON), keyProvider: { "key" })
        let template = StageTemplate(stage: .factCheck, systemPrompt: "sys", userPromptTemplate: "{{текущий_текст}}")

        await executor.executeQuickCheck(stage: .factCheck, pastedText: "текст", template: template, in: context)

        let jobs = try context.fetch(FetchDescriptor<GenerationJob>())
        let versions = try context.fetch(FetchDescriptor<ArticleVersion>())
        #expect(jobs.isEmpty)
        #expect(versions.isEmpty)
    }
}

struct QuickCheckTitleTests {
    @Test func usesFirstNonEmptyLine() {
        #expect(QuickCheckTitle.suggest(from: "\n  \nЗаголовок статьи\nостальное") == "Заголовок статьи")
    }

    @Test func trimsAndCapsLength() {
        let long = String(repeating: "а", count: 200)
        #expect(QuickCheckTitle.suggest(from: long).count == 80)
    }

    @Test func fallbackForEmptyText() {
        #expect(QuickCheckTitle.suggest(from: "   \n  ") == "Быстрая проверка")
    }
}
