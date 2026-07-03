import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ExternalDocumentTests {
    private func ctx() throws -> ModelContext {
        let container = try ModelContainer(
            for: Topic.self, PromptRecommendation.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, PersistedRemark.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
                 GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
                 ExternalDocument.self, SemanticKeyword.self, PublishedSitePage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func storesPublicationAndLinksToTopic() throws {
        let ctx = try ctx()
        let topic = Topic(title: "Тема", articleType: .info)
        ctx.insert(topic)
        let doc = ExternalDocument(docID: "doc123", docURL: "https://docs.google.com/document/d/doc123/edit", mode: .newDocument)
        doc.topic = topic
        ctx.insert(doc)
        try ctx.save()

        #expect(topic.publications.count == 1)
        #expect(topic.publications.first?.docID == "doc123")
        #expect(topic.publications.first?.mode == .newDocument)
    }
}
