import Foundation
import SwiftData

@Model
final class Topic {
    var title: String
    /// Внешний ID темы из пользовательской таблицы (вписывается вручную).
    /// Используется в заголовке публикуемого документа: «№[ID] [Тема] — …».
    var externalID: String = ""
    var articleTypeRaw: String
    var targetVolume: Int?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var externalDocURL: String?
    var publishedAt: Date?
    var currentVersionID: UUID?
    var coverImageID: UUID?
    var semantics: [String]
    var structureText: String = ""

    @Relationship var direction: KnowledgeNode?
    @Relationship var doctor: KnowledgeNode?
    @Relationship var attachedNodes: [KnowledgeNode]
    @Relationship(deleteRule: .cascade, inverse: \ArticleVersion.topic)
    var versions: [ArticleVersion]
    @Relationship(deleteRule: .cascade, inverse: \GenerationJob.topic)
    var jobs: [GenerationJob]
    @Relationship(deleteRule: .cascade, inverse: \GeneratedImage.topic)
    var images: [GeneratedImage]
    @Relationship(deleteRule: .cascade, inverse: \ExternalDocument.topic)
    var publications: [ExternalDocument] = []
    @Relationship(deleteRule: .cascade, inverse: \SemanticKeyword.topic)
    var semanticKeywords: [SemanticKeyword]

    init(
        title: String,
        articleType: ArticleType,
        externalID: String = "",
        targetVolume: Int? = nil,
        direction: KnowledgeNode? = nil,
        doctor: KnowledgeNode? = nil,
        notes: String = ""
    ) {
        self.title = title
        self.externalID = externalID
        self.articleTypeRaw = articleType.rawValue
        self.targetVolume = targetVolume
        self.direction = direction
        self.doctor = doctor
        self.attachedNodes = []
        self.semantics = []
        self.structureText = ""
        self.versions = []
        self.jobs = []
        self.images = []
        self.publications = []
        self.semanticKeywords = []
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
    }

    var articleType: ArticleType {
        get { ArticleType(rawValue: articleTypeRaw) ?? .info }
        set { articleTypeRaw = newValue.rawValue }
    }

    var currentVersion: ArticleVersion? {
        guard let id = currentVersionID else { return nil }
        return versions.first { $0.uuid == id }
    }
}
