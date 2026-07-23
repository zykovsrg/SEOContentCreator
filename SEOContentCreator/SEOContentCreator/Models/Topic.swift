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
    /// Ссылка на подпапку Google Drive с иллюстрациями этой статьи.
    /// Появляется после первой публикации с загрузкой картинок.
    var illustrationsFolderURL: String?
    var semantics: [String]
    var structureText: String = ""

    @Relationship(deleteRule: .nullify, inverse: \KnowledgeNode.topicsUsingAsDirection) var direction: KnowledgeNode?
    @Relationship(deleteRule: .nullify, inverse: \KnowledgeNode.topicsUsingAsDoctor) var doctor: KnowledgeNode?
    /// Дополнительные направления для раздела «Техническая информация».
    /// Основное `direction` остаётся единственным источником для промтов.
    @Relationship var additionalDirections: [KnowledgeNode] = []
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
    @Relationship(deleteRule: .cascade, inverse: \SemanticFunnelEntry.topic)
    var funnelEntries: [SemanticFunnelEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \PromptRecommendation.topic)
    var promptRecommendations: [PromptRecommendation] = []
    @Relationship(deleteRule: .cascade, inverse: \ReaderIntent.topic)
    var readerIntent: ReaderIntent?
    @Relationship(deleteRule: .cascade, inverse: \SemanticCollectionCheckpoint.topic)
    var collectionCheckpoint: SemanticCollectionCheckpoint?

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
        self.additionalDirections = []
        self.semantics = []
        self.structureText = ""
        self.versions = []
        self.jobs = []
        self.images = []
        self.publications = []
        self.semanticKeywords = []
        self.promptRecommendations = []
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

    /// Sum of prompt+completion tokens across every GenerationJob for this topic.
    /// Jobs that predate FT-20260702-005, or errored before the usage chunk arrived, count as 0.
    var totalTokenCost: Int {
        jobs.reduce(0) { $0 + ($1.promptTokens ?? 0) + ($1.completionTokens ?? 0) }
    }
}
