import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct StageTemplateSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
                 GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
                 ExternalDocument.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "StageTemplateSeederTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func seedsOneTemplatePerStage() throws {
        let context = try makeContext()
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: makeDefaults())
        let all = try context.fetch(FetchDescriptor<StageTemplate>())
        #expect(all.count == PipelineStage.allCases.count)
        for stage in PipelineStage.allCases {
            #expect(all.contains { $0.stageRaw == stage.rawValue })
        }
    }

    @Test func seedingIsIdempotent() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        let all = try context.fetch(FetchDescriptor<StageTemplate>())
        #expect(all.count == PipelineStage.allCases.count)
        #expect(try context.fetch(FetchDescriptor<ContextBlock>()).count == 3)
        #expect(try context.fetch(FetchDescriptor<AIRole>()).count == 4)
    }

    @Test func seedsDefaultContextBlocksAndRoles() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        let blocks = try context.fetch(FetchDescriptor<ContextBlock>())
        let roles = try context.fetch(FetchDescriptor<AIRole>())
        #expect(Set(blocks.map(\.key)) == ["editorialPolicy", "sources", "seoGuidelines"])
        #expect(Set(roles.map(\.key)) == ["author", "seo", "factChecker", "editor"])
        #expect(roles.first { $0.key == "author" }?.blockKeys == ["editorialPolicy", "sources"])
        #expect(roles.first { $0.key == "seo" }?.blockKeys == ["seoGuidelines"])
        #expect(roles.first { $0.key == "factChecker" }?.blockKeys == ["sources"])
        #expect(roles.first { $0.key == "editor" }?.blockKeys == ["editorialPolicy"])
    }

    @Test func migrationReplacesOnlySystemPromptAndStoresDefaultsVersion() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        defaults.set(1, forKey: StageTemplateSeeder.templatesDefaultsVersionKey)
        let old = StageTemplate(
            stage: .draft,
            systemPrompt: "Старый длинный системный промт",
            userPromptTemplate: "Пользовательский {{тема}}",
            modelName: "gpt-4o",
            temperature: 0.2,
            maxTokens: 4000
        )
        context.insert(old)

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(old.systemPrompt == StageTemplateDefaults.content(for: .draft).systemPrompt)
        #expect(old.userPromptTemplate == "Пользовательский {{тема}}")
        #expect(old.modelName == "gpt-4o")
        #expect(old.temperature == 0.2)
        #expect(old.maxTokens == 4000)
        #expect(defaults.integer(forKey: StageTemplateSeeder.templatesDefaultsVersionKey) == 2)

        old.systemPrompt = "Ручная правка после миграции"
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        #expect(old.systemPrompt == "Ручная правка после миграции")
    }
}
