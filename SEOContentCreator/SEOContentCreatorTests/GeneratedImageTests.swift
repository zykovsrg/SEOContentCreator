import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct GeneratedImageTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self, GeneratedImage.self, ExternalDocument.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func imageJoinsTopicGalleryAndRoleRoundTrips() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)

        let image = GeneratedImage(role: .cover, data: Data([1, 2, 3]), promptUsed: "промт")
        image.topic = topic
        context.insert(image)

        #expect(topic.images.count == 1)
        #expect(topic.images.first?.role == .cover)
        #expect(topic.images.first?.data == Data([1, 2, 3]))
        #expect(topic.images.first?.anchorQuote == nil)
        #expect(topic.coverImageID == nil)
    }

    @Test func illustrationStoresAnchorAndSource() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let parentID = UUID()
        let image = GeneratedImage(role: .illustration, data: Data([9]), promptUsed: "p",
                                   anchorQuote: "фрагмент", sourceImageID: parentID)
        image.topic = topic
        context.insert(image)

        #expect(image.role == .illustration)
        #expect(image.anchorQuote == "фрагмент")
        #expect(image.sourceImageID == parentID)
    }
}
