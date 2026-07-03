import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct StageTemplateSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, PromptRecommendation.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, PersistedRemark.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
                 GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
                 ExternalDocument.self, SemanticKeyword.self, PublishedSitePage.self,
                 SkillPreset.self,
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
        let chatStages = PipelineStage.allCases.filter { $0.kind != .action }
        #expect(all.count == chatStages.count)
        for stage in chatStages {
            #expect(all.contains { $0.stageRaw == stage.rawValue })
        }
        #expect(!all.contains { $0.stageRaw == PipelineStage.images.rawValue })
    }

    @Test func seedingIsIdempotent() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        let all = try context.fetch(FetchDescriptor<StageTemplate>())
        #expect(all.count == PipelineStage.allCases.filter { $0.kind != .action }.count)
        #expect(try context.fetch(FetchDescriptor<ContextBlock>()).count == 3)
        #expect(try context.fetch(FetchDescriptor<AIRole>()).count == 5)
    }

    @Test func seedsDefaultContextBlocksAndRoles() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        let blocks = try context.fetch(FetchDescriptor<ContextBlock>())
        let roles = try context.fetch(FetchDescriptor<AIRole>())
        #expect(Set(blocks.map(\.key)) == ["editorialPolicy", "sources", "seoGuidelines"])
        #expect(Set(roles.map(\.key)) == ["author", "seo", "factChecker", "editor", "analyst"])
        #expect(roles.first { $0.key == "author" }?.blockKeys == ["editorialPolicy", "sources"])
        #expect(roles.first { $0.key == "seo" }?.blockKeys == ["seoGuidelines"])
        #expect(roles.first { $0.key == "factChecker" }?.blockKeys == ["sources"])
        #expect(roles.first { $0.key == "editor" }?.blockKeys == ["editorialPolicy"])
        #expect(roles.first { $0.key == "analyst" }?.blockKeys == [])
    }

    @Test func migrationUpdatesCascadeTemplatesAndStoresDefaultsVersion() throws {
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
        let oldProductBlocks = StageTemplate(
            stage: .productBlocks,
            systemPrompt: "product blocks system",
            userPromptTemplate: "Пользовательский productBlocks"
        )
        context.insert(old)
        context.insert(oldProductBlocks)

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(old.systemPrompt == StageTemplateDefaults.content(for: .draft).systemPrompt)
        #expect(old.userPromptTemplate == StageTemplateDefaults.content(for: .draft).userPromptTemplate)
        #expect(old.modelName == "gpt-4o")
        #expect(old.temperature == 0.2)
        #expect(old.maxTokens == 4000)
        // productBlocks is not part of the cascade, so its custom content survives migration.
        #expect(oldProductBlocks.systemPrompt == "product blocks system")
        #expect(oldProductBlocks.userPromptTemplate == "Пользовательский productBlocks")
        #expect(defaults.integer(forKey: StageTemplateSeeder.templatesDefaultsVersionKey) == 6)

        old.userPromptTemplate = "Ручная правка после миграции"
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        #expect(old.userPromptTemplate == "Ручная правка после миграции")
    }

    @Test func migrationAddsAnalystRoleToPreExistingInstallationsWithoutIt() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        defaults.set(5, forKey: StageTemplateSeeder.templatesDefaultsVersionKey)
        // Simulates a database seeded before the "analyst" role existed.
        for def in RoleDefaults.all where def.key != "analyst" {
            context.insert(AIRole(key: def.key, name: def.name, mandate: def.mandate, blockKeys: def.blockKeys))
        }

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        let roles = try context.fetch(FetchDescriptor<AIRole>())
        #expect(roles.contains { $0.key == "analyst" })
        #expect(defaults.integer(forKey: StageTemplateSeeder.templatesDefaultsVersionKey) == 6)
    }
}
