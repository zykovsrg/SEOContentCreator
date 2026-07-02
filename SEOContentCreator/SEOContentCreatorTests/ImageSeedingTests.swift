import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ImageSeedingTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
                 GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
                 ExternalDocument.self, SemanticKeyword.self, PublishedSitePage.self,
                 SkillPreset.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ImageSeedingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func seedsOnePromptTemplatePerKindAndOnePreset() throws {
        let context = try makeContext()
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: makeDefaults())

        let templates = try context.fetch(FetchDescriptor<ImagePromptTemplate>())
        #expect(templates.count == ImagePromptKind.allCases.count)
        for kind in ImagePromptKind.allCases {
            #expect(templates.contains { $0.kindRaw == kind.rawValue })
        }
        let presets = try context.fetch(FetchDescriptor<ImageStylePreset>())
        #expect(presets.count == 1)
        #expect(presets.first?.name == ImageStylePresetDefaults.name)
    }

    @Test func imageSeedingIsIdempotent() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(try context.fetch(FetchDescriptor<ImagePromptTemplate>()).count == ImagePromptKind.allCases.count)
        #expect(try context.fetch(FetchDescriptor<ImageStylePreset>()).count == 1)
    }
}
