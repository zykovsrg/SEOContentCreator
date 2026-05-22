import Foundation
import SwiftData

@Model
final class Topic {
    var title: String
    var articleTypeRaw: String
    var targetVolume: Int?
    var notes: String
    var useStyle: Bool
    var createdAt: Date
    var updatedAt: Date
    var externalDocURL: String?
    var publishedAt: Date?

    @Relationship var direction: KnowledgeNode?
    @Relationship var doctor: KnowledgeNode?
    @Relationship var attachedNodes: [KnowledgeNode]

    init(
        title: String,
        articleType: ArticleType,
        targetVolume: Int? = nil,
        direction: KnowledgeNode? = nil,
        doctor: KnowledgeNode? = nil,
        notes: String = "",
        useStyle: Bool = false
    ) {
        self.title = title
        self.articleTypeRaw = articleType.rawValue
        self.targetVolume = targetVolume
        self.direction = direction
        self.doctor = doctor
        self.attachedNodes = []
        self.notes = notes
        self.useStyle = useStyle
        self.createdAt = .now
        self.updatedAt = .now
    }

    var articleType: ArticleType {
        get { ArticleType(rawValue: articleTypeRaw) ?? .info }
        set { articleTypeRaw = newValue.rawValue }
    }
}
