import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ImageSaverTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, PromptRecommendation.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, PersistedRemark.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
                 GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
                 ExternalDocument.self, SemanticKeyword.self, PublishedSitePage.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func firstCoverSetsCoverImageID() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)

        let image = ImageSaver.saveGenerated(
            data: Data([1]), role: .cover, prompt: "p", fragment: nil,
            preset: nil, model: "m", topic: topic, in: context
        )
        #expect(topic.images.count == 1)
        #expect(topic.coverImageID == image.uuid)
        #expect(image.role == .cover)
        #expect(image.anchorQuote == nil)
    }

    @Test func illustrationStoresAnchorAndDoesNotSetCover() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)

        let image = ImageSaver.saveGenerated(
            data: Data([2]), role: .illustration, prompt: "p", fragment: "фрагмент",
            preset: nil, model: "m", topic: topic, in: context
        )
        #expect(image.anchorQuote == "фрагмент")
        #expect(topic.coverImageID == nil)
    }

    @Test func refineInheritsRoleAndAnchorAndLinksSource() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let source = ImageSaver.saveGenerated(
            data: Data([3]), role: .illustration, prompt: "p", fragment: "якорь",
            preset: nil, model: "m", topic: topic, in: context
        )

        let refined = ImageSaver.saveRefined(
            data: Data([4]), source: source, prompt: "сделай светлее",
            preset: nil, model: "m", topic: topic, in: context
        )
        #expect(topic.images.count == 2)
        #expect(refined.role == .illustration)
        #expect(refined.anchorQuote == "якорь")
        #expect(refined.sourceImageID == source.uuid)
        #expect(source.data == Data([3]))
    }
}
