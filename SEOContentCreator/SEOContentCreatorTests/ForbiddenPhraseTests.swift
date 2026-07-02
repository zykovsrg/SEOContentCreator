import Testing
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ForbiddenPhraseTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ForbiddenPhrase.self, configurations: config)
        return ModelContext(container)
    }

    @Test func seedsFiveDefaultPhrasesOnce() throws {
        let context = try makeContext()

        ForbiddenPhraseSeeder.seedIfNeeded(in: context)
        ForbiddenPhraseSeeder.seedIfNeeded(in: context)

        let phrases = try context.fetch(FetchDescriptor<ForbiddenPhrase>())
        #expect(phrases.count == 5)
        #expect(phrases.contains { $0.phrase == "кровянистое отделяемое" })
    }

    @Test func rendersPhrasesForPrompt() {
        let phrase = ForbiddenPhrase(
            phrase: "кровянистое отделяемое",
            problem: "плохо звучит",
            replacement: "кровянистые выделения",
            order: 0
        )

        let rendered = ForbiddenPhraseRenderer.render([phrase])

        #expect(rendered.contains("«кровянистое отделяемое»"))
        #expect(rendered.contains("плохо звучит"))
        #expect(rendered.contains("«кровянистые выделения»"))
    }

    @Test func rendersEmptyListPlaceholder() {
        #expect(ForbiddenPhraseRenderer.render([]) == "(список пуст)")
    }
}
