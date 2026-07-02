import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

final class FakeDocsClient: DocsPublishing {
    nonisolated(unsafe) var created: [String] = []
    nonisolated(unsafe) var batched: [(String, [[String: Any]])] = []
    nonisolated(unsafe) var cleared: [String] = []
    nonisolated(unsafe) var moved: [(String, String)] = []
    nonisolated(unsafe) var nextDocID = "doc-new"
    nonisolated(unsafe) var bodyEndIndex = 20
    nonisolated(unsafe) var failBatchUpdate = false

    func createDocument(title: String) async throws -> String { created.append(title); return nextDocID }
    func batchUpdate(docID: String, requests: [[String: Any]]) async throws {
        if failBatchUpdate { throw GoogleDocsClient.DocsError.http(500) }
        batched.append((docID, requests))
    }
    func clearBody(docID: String) async throws { cleared.append(docID) }
    func documentBodyEndIndex(docID: String) async throws -> Int { bodyEndIndex }
    func findOrCreateFolder(name: String) async throws -> String { "folder-1" }
    func moveToFolder(fileID: String, folderID: String) async throws { moved.append((fileID, folderID)) }
}

@MainActor
struct ArticlePublisherTests {
    private func ctx() throws -> ModelContext {
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
                 GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
                 ExternalDocument.self, SemanticKeyword.self, PublishedSitePage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func topicWithText(_ ctx: ModelContext, _ text: String) -> Topic {
        let t = Topic(title: "Тема", articleType: .info)
        ctx.insert(t)
        let v = ArticleVersion(stage: .draft, source: .generated, text: text, agentName: "ИИ-автор", templateID: UUID(), modelName: "gpt-4.1")
        v.topic = t
        ctx.insert(v)
        t.currentVersionID = v.uuid
        return t
    }

    @Test func newDocumentCreatesAndRecords() async throws {
        let context = try ctx()
        let topic = topicWithText(context, "# Заголовок\nАбзац.")
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")
        await publisher.publish(topic: topic, mode: .newDocument, in: context)

        #expect(publisher.lastErrorMessage == nil)
        #expect(fake.created == ["Тема — Контент для страницы"])
        #expect(fake.moved.first?.1 == "folder-1")
        #expect(topic.publications.count == 1)
        #expect(topic.externalDocURL?.contains("doc-new") == true)
        #expect(topic.publishedAt != nil)
    }

    @Test func overwriteReusesExistingDocAndReplacesBody() async throws {
        let context = try ctx()
        let topic = topicWithText(context, "Текст")
        let prev = ExternalDocument(docID: "doc-old", docURL: GoogleDocsClient.documentURL(id: "doc-old"), mode: .newDocument)
        prev.topic = topic; context.insert(prev)
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")
        await publisher.publish(topic: topic, mode: .overwrite, in: context)

        #expect(fake.created.isEmpty)
        #expect(fake.cleared.isEmpty)
        #expect(fake.batched.first?.0 == "doc-old")
        #expect(fake.batched.first?.1.first?["deleteContentRange"] != nil)
    }

    @Test func noCurrentVersionSetsError() async throws {
        let context = try ctx()
        let topic = Topic(title: "Пустая", articleType: .info)
        context.insert(topic)
        let publisher = ArticlePublisher(docs: FakeDocsClient(), tokenProvider: { "t" }, folderName: "f")
        await publisher.publish(topic: topic, mode: .newDocument, in: context)
        #expect(publisher.lastErrorMessage != nil)
        #expect(topic.publications.isEmpty)
    }

    @Test func overwriteDoesNotRecordPublicationWhenReplacementFails() async throws {
        let context = try ctx()
        let topic = topicWithText(context, "Текст")
        let prev = ExternalDocument(docID: "doc-old", docURL: GoogleDocsClient.documentURL(id: "doc-old"), mode: .newDocument)
        prev.topic = topic
        context.insert(prev)
        let fake = FakeDocsClient()
        fake.failBatchUpdate = true
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")

        await publisher.publish(topic: topic, mode: .overwrite, targetDocID: "doc-old", in: context)

        #expect(publisher.lastErrorMessage != nil)
        #expect(topic.publications.count == 1)
        #expect(fake.cleared.isEmpty)
    }
}
