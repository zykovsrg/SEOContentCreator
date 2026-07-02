import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ImagePersistenceModelsTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
                 GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
                 ExternalDocument.self, SemanticKeyword.self, PublishedSitePage.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func presetStoresFields() throws {
        let context = try makeContext()
        let preset = ImageStylePreset(name: "Бренд", styleText: "палитра", size: "1024x1024", quality: "high")
        context.insert(preset)
        let all = try context.fetch(FetchDescriptor<ImageStylePreset>())
        #expect(all.count == 1)
        #expect(all.first?.name == "Бренд")
        #expect(all.first?.styleText == "палитра")
        #expect(all.first?.referenceImageData == nil)
    }

    @Test func promptTemplateKindRoundTrips() throws {
        let context = try makeContext()
        let t = ImagePromptTemplate(kind: .illustration, userPromptTemplate: "{{тема}}")
        context.insert(t)
        let all = try context.fetch(FetchDescriptor<ImagePromptTemplate>())
        #expect(all.first?.kind == .illustration)
        #expect(all.first?.userPromptTemplate == "{{тема}}")
    }
}
