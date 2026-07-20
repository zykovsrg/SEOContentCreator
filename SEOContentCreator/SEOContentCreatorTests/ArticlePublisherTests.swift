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
    nonisolated(unsafe) var subfolders: [(name: String, parentID: String)] = []
    nonisolated(unsafe) var uploads: [(name: String, parentID: String, byteCount: Int)] = []
    nonisolated(unsafe) var failUpload = false
    nonisolated(unsafe) var nextFileIDNumber = 1

    func createDocument(title: String) async throws -> String { created.append(title); return nextDocID }
    func batchUpdate(docID: String, requests: [[String: Any]]) async throws {
        if failBatchUpdate { throw GoogleDocsClient.DocsError.http(500) }
        batched.append((docID, requests))
    }
    func clearBody(docID: String) async throws { cleared.append(docID) }
    func documentBodyEndIndex(docID: String) async throws -> Int { bodyEndIndex }
    func findOrCreateFolder(name: String) async throws -> String { "folder-1" }
    func findOrCreateFolder(name: String, parentID: String) async throws -> String {
        subfolders.append((name, parentID))
        return "sub-\(name)"
    }
    func uploadFile(name: String, data: Data, mimeType: String, parentID: String) async throws -> String {
        if failUpload { throw GoogleDocsClient.DocsError.http(500) }
        uploads.append((name, parentID, data.count))
        defer { nextFileIDNumber += 1 }
        return "file-\(nextFileIDNumber)"
    }
    func moveToFolder(fileID: String, folderID: String) async throws { moved.append((fileID, folderID)) }
}

@MainActor
struct ArticlePublisherTests {
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

    @Test func normalizeHeadingReplacesExistingH1() {
        let result = ArticlePublisher.normalizeHeading(text: "# Старый заголовок\nАбзац.", h1: "Новый H1")
        #expect(result == "# Новый H1\nАбзац.")
    }

    @Test func normalizeHeadingInsertsWhenMissing() {
        let result = ArticlePublisher.normalizeHeading(text: "Просто абзац без заголовка.", h1: "Новый H1")
        #expect(result == "# Новый H1\nПросто абзац без заголовка.")
    }

    @Test func normalizeHeadingKeepsTextWhenH1Nil() {
        let result = ArticlePublisher.normalizeHeading(text: "# Заголовок\nАбзац.", h1: nil)
        #expect(result == "# Заголовок\nАбзац.")
    }

    @Test func publishUsesNormalizedH1InRequestBody() async throws {
        let context = try ctx()
        let topic = Topic(title: "Тема", articleType: .info)
        context.insert(topic)
        let version = ArticleVersion(stage: .semanticsInText, source: .generated, text: "# Старый\nАбзац.")
        version.h1 = "SEO H1"
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "f")

        await publisher.publish(topic: topic, mode: .newDocument, in: context)

        let insertedText = fake.batched.first?.1.first?["insertText"] as? [String: Any]
        #expect((insertedText?["text"] as? String)?.contains("SEO H1") == true)
    }

    @Test func publishWrapsCommercialBlockInTable() async throws {
        let context = try ctx()
        let topic = topicWithText(context, "Обычный текст.\n\n[[БЛОК]]\nКоммерческий текст.\n[[/БЛОК]]\n\nЕщё текст.")
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "f")

        await publisher.publish(topic: topic, mode: .newDocument, in: context)

        #expect(publisher.lastErrorMessage == nil)
        let requests = fake.batched.first?.1 ?? []
        let hasTable = requests.contains { $0["insertTable"] != nil }
        #expect(hasTable)
        let insertedTexts = requests.compactMap { ($0["insertText"] as? [String: Any])?["text"] as? String }
        #expect(insertedTexts.contains { $0.contains("Коммерческий текст.") })
        #expect(!insertedTexts.contains { $0.contains("[[БЛОК]]") })
        #expect(!insertedTexts.contains { $0.contains("[[/БЛОК]]") })
    }
}
