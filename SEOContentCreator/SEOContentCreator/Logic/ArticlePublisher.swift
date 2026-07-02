import Foundation
import SwiftData

protocol DocsPublishing {
    func createDocument(title: String) async throws -> String
    func batchUpdate(docID: String, requests: [[String: Any]]) async throws
    func clearBody(docID: String) async throws
    func documentBodyEndIndex(docID: String) async throws -> Int
    func findOrCreateFolder(name: String) async throws -> String
    func moveToFolder(fileID: String, folderID: String) async throws
}

extension GoogleDocsClient: DocsPublishing {}

@MainActor
@Observable
final class ArticlePublisher {
    var isPublishing = false
    var lastErrorMessage: String?

    private let docs: DocsPublishing
    private let tokenProvider: () async throws -> String
    private let folderName: String

    init(docs: DocsPublishing, tokenProvider: @escaping () async throws -> String,
         folderName: String = "SEO-статьи клиники") {
        self.docs = docs
        self.tokenProvider = tokenProvider
        self.folderName = folderName
    }

    static func live(auth: GoogleAuthService) -> ArticlePublisher {
        let client = GoogleDocsClient(tokenProvider: { try await auth.validAccessToken() })
        return ArticlePublisher(docs: client, tokenProvider: { try await auth.validAccessToken() })
    }

    func publish(topic: Topic, mode: PublishMode, targetDocID: String? = nil, in context: ModelContext) async {
        isPublishing = true
        lastErrorMessage = nil
        defer { isPublishing = false }

        guard let version = topic.currentVersion, !version.text.isEmpty else {
            lastErrorMessage = "Нет принятой версии текста для публикации."
            return
        }
        do {
            _ = try await tokenProvider()
            let blocks = MarkdownDocParser.parse(Self.normalizeHeading(text: version.text, h1: version.h1))
            let requests = DocsRequestBuilder.build(blocks: blocks)

            let docTitle = PublishTitleBuilder.title(externalID: topic.externalID, topicTitle: topic.title)
            let docID: String
            switch mode {
            case .newDocument:
                docID = try await docs.createDocument(title: docTitle)
            case .overwrite:
                guard let existing = targetDocID
                        ?? topic.publications.sorted(by: { $0.publishedAt > $1.publishedAt }).first?.docID
                        ?? topic.externalDocURL.flatMap(Self.docID(fromURL:)) else {
                    let id = try await docs.createDocument(title: docTitle)
                    try await fill(docID: id, requests: requests)
                    try await place(docID: id)
                    record(topic: topic, docID: id, mode: .newDocument, in: context)
                    return
                }
                docID = existing
                let endIndex = try await docs.documentBodyEndIndex(docID: docID)
                let replacementRequests = DocsRequestBuilder.buildReplacingBody(blocks: blocks, existingBodyEndIndex: endIndex)
                try await fill(docID: docID, requests: replacementRequests)
                record(topic: topic, docID: docID, mode: mode, in: context)
                return
            }

            try await fill(docID: docID, requests: requests)
            if mode == .newDocument { try await place(docID: docID) }
            record(topic: topic, docID: docID, mode: mode, in: context)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fill(docID: String, requests: [[String: Any]]) async throws {
        try await docs.batchUpdate(docID: docID, requests: requests)
    }

    private func place(docID: String) async throws {
        let folder = try await docs.findOrCreateFolder(name: folderName)
        try await docs.moveToFolder(fileID: docID, folderID: folder)
    }

    private func record(topic: Topic, docID: String, mode: PublishMode, in context: ModelContext) {
        let url = GoogleDocsClient.documentURL(id: docID)
        let doc = ExternalDocument(docID: docID, docURL: url, mode: mode)
        doc.topic = topic
        context.insert(doc)
        topic.externalDocURL = url
        topic.publishedAt = .now
    }

    /// Публикуемый документ должен показывать SEO-утверждённый H1 (из этапа
    /// «Семантика-в-текст»), а не только заголовок, который уже был в тексте
    /// черновика. Title/Description сознательно НЕ публикуются в тело
    /// документа — это метаданные для сайта, а не для читателя документа.
    static func normalizeHeading(text: String, h1: String?) -> String {
        guard let h1, !h1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        var lines = text.components(separatedBy: "\n")
        if let first = lines.first, first.hasPrefix("# ") {
            lines[0] = "# \(h1)"
        } else {
            lines.insert("# \(h1)", at: 0)
        }
        return lines.joined(separator: "\n")
    }

    static func docID(fromURL url: String) -> String? {
        guard let range = url.range(of: "/document/d/") else { return nil }
        let tail = url[range.upperBound...]
        return tail.components(separatedBy: "/").first
    }
}
