import Foundation
import SwiftData

@Model
final class ImagePromptTemplate {
    var uuid: UUID
    var kindRaw: String
    var userPromptTemplate: String
    var createdAt: Date
    var updatedAt: Date

    init(kind: ImagePromptKind, userPromptTemplate: String) {
        self.uuid = UUID()
        self.kindRaw = kind.rawValue
        self.userPromptTemplate = userPromptTemplate
        self.createdAt = .now
        self.updatedAt = .now
    }

    var kind: ImagePromptKind? { ImagePromptKind(rawValue: kindRaw) }
}
