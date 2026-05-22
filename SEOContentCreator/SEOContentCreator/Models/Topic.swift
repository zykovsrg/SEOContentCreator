import Foundation
import SwiftData

@Model
final class Topic {
    var id: UUID
    var title: String
    var articleTypeRaw: String
    var targetVolume: Int?
    var direction: String   // plain text for now; becomes a Knowledge Base node in sub-project 2
    var doctor: String      // plain text for now
    var notes: String
    var useStyle: Bool
    var createdAt: Date
    var updatedAt: Date
    var externalDocURL: String?
    var publishedAt: Date?

    init(
        title: String,
        articleType: ArticleType,
        targetVolume: Int? = nil,
        direction: String = "",
        doctor: String = "",
        notes: String = "",
        useStyle: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.articleTypeRaw = articleType.rawValue
        self.targetVolume = targetVolume
        self.direction = direction
        self.doctor = doctor
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
