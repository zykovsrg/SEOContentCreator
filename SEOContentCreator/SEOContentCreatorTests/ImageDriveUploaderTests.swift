import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ImageDriveUploaderTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, KnowledgeNode.self, ArticleVersion.self, GeneratedImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func image(role: ImageRole, topic: Topic, ctx: ModelContext) -> GeneratedImage {
        let img = GeneratedImage(role: role, data: Data([1, 2, 3]), promptUsed: "p")
        img.topic = topic
        ctx.insert(img)
        return img
    }

    @Test func topicFolderNameUsesExternalID() {
        #expect(ImageDriveUploader.topicFolderName(externalID: "12", topicTitle: "Тема") == "№12 Тема")
        #expect(ImageDriveUploader.topicFolderName(externalID: "  ", topicTitle: "Тема") == "Тема")
    }

    @Test func fileNamesByRoleAndIndex() {
        #expect(ImageDriveUploader.fileName(role: .cover, index: 1) == "обложка.png")
        #expect(ImageDriveUploader.fileName(role: .cover, index: 2) == "обложка-2.png")
        #expect(ImageDriveUploader.fileName(role: .illustration, index: 1) == "иллюстрация-1.png")
    }

    @Test func uploadsIntoNestedFolderAndMarksImages() async throws {
        let ctx = try makeContext()
        let topic = Topic(title: "Тема", articleType: .info, externalID: "7")
        ctx.insert(topic)
        let cover = image(role: .cover, topic: topic, ctx: ctx)
        let ill = image(role: .illustration, topic: topic, ctx: ctx)
        let fake = FakeDocsClient()

        let result = try await ImageDriveUploader.upload(
            images: [cover, ill], topic: topic, drive: fake, rootFolderName: "SEO-статьи клиники")

        // Folder chain: root (existing API) → «Иллюстрации» → topic subfolder.
        #expect(fake.subfolders.map(\.name) == ["Иллюстрации", "№7 Тема"])
        #expect(fake.subfolders[1].parentID == "sub-Иллюстрации")
        #expect(fake.uploads.map(\.name) == ["обложка.png", "иллюстрация-1.png"])
        #expect(cover.driveFileID == "file-1")
        #expect(ill.driveFileID == "file-2")
        #expect(result.uploadedCount == 2)
        #expect(result.skippedCount == 0)
        #expect(result.folderURL == GoogleDocsClient.folderURL(id: "sub-№7 Тема"))
    }

    @Test func skipsAlreadyUploadedImages() async throws {
        let ctx = try makeContext()
        let topic = Topic(title: "Тема", articleType: .info)
        ctx.insert(topic)
        let done = image(role: .illustration, topic: topic, ctx: ctx)
        done.driveFileID = "already-there"
        let fresh = image(role: .illustration, topic: topic, ctx: ctx)
        let fake = FakeDocsClient()

        let result = try await ImageDriveUploader.upload(
            images: [done, fresh], topic: topic, drive: fake, rootFolderName: "R")

        #expect(fake.uploads.count == 1)
        // Numbering stays stable: the skipped image keeps slot 1, the new one is 2.
        #expect(fake.uploads.first?.name == "иллюстрация-2.png")
        #expect(result.uploadedCount == 1)
        #expect(result.skippedCount == 1)
        #expect(done.driveFileID == "already-there")
    }
}
