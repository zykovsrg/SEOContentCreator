import Foundation
import SwiftData

@Model
final class GeneratedImage {
    var uuid: UUID
    var roleRaw: String
    @Attribute(.externalStorage) var data: Data
    var promptUsed: String
    var presetID: UUID?
    var presetNameSnapshot: String?
    var anchorQuote: String?
    var sourceImageID: UUID?
    var modelName: String?
    var createdAt: Date
    var isArchived: Bool

    @Relationship var topic: Topic?

    init(
        role: ImageRole,
        data: Data,
        promptUsed: String,
        presetID: UUID? = nil,
        presetNameSnapshot: String? = nil,
        anchorQuote: String? = nil,
        sourceImageID: UUID? = nil,
        modelName: String? = nil
    ) {
        self.uuid = UUID()
        self.roleRaw = role.rawValue
        self.data = data
        self.promptUsed = promptUsed
        self.presetID = presetID
        self.presetNameSnapshot = presetNameSnapshot
        self.anchorQuote = anchorQuote
        self.sourceImageID = sourceImageID
        self.modelName = modelName
        self.isArchived = false
        self.createdAt = .now
    }

    var role: ImageRole {
        get { ImageRole(rawValue: roleRaw) ?? .illustration }
        set { roleRaw = newValue.rawValue }
    }
}
