import Foundation

/// Загружает выбранные картинки темы в подпапку статьи на Google Диске:
/// `<root>/Иллюстрации/№[ID] [Тема]/`. Уже загруженные (driveFileID != nil)
/// пропускаются; нумерация имён файлов при этом не сдвигается.
@MainActor
enum ImageDriveUploader {
    struct UploadResult: Equatable {
        var folderID: String
        var folderURL: String
        var uploadedCount: Int
        var skippedCount: Int
    }

    static let illustrationsFolderName = "Иллюстрации"

    static func topicFolderName(externalID: String, topicTitle: String) -> String {
        let id = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = topicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? name : "№\(id) \(name)"
    }

    static func fileName(role: ImageRole, index: Int) -> String {
        switch role {
        case .cover:        return index == 1 ? "обложка.png" : "обложка-\(index).png"
        case .illustration: return "иллюстрация-\(index).png"
        }
    }

    static func upload(images: [GeneratedImage], topic: Topic, drive: DocsPublishing,
                       rootFolderName: String) async throws -> UploadResult {
        let root = try await drive.findOrCreateFolder(name: rootFolderName)
        let illustrations = try await drive.findOrCreateFolder(
            name: illustrationsFolderName, parentID: root)
        let topicFolder = try await drive.findOrCreateFolder(
            name: topicFolderName(externalID: topic.externalID, topicTitle: topic.title),
            parentID: illustrations)

        var uploaded = 0
        var skipped = 0
        var coverIndex = 0
        var illustrationIndex = 0
        for image in images.sorted(by: { $0.createdAt < $1.createdAt }) {
            let index: Int
            if image.role == .cover { coverIndex += 1; index = coverIndex }
            else { illustrationIndex += 1; index = illustrationIndex }
            if image.driveFileID != nil { skipped += 1; continue }
            let fileID = try await drive.uploadFile(
                name: fileName(role: image.role, index: index),
                data: image.data, mimeType: "image/png", parentID: topicFolder)
            image.driveFileID = fileID
            uploaded += 1
        }
        return UploadResult(
            folderID: topicFolder,
            folderURL: GoogleDocsClient.folderURL(id: topicFolder),
            uploadedCount: uploaded, skippedCount: skipped)
    }
}
