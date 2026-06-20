import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ExternalDocumentTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Topic.self, ExternalDocument.self, ArticleVersion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func storesPublicationAndLinksToTopic() throws {
        let ctx = try container().mainContext
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
