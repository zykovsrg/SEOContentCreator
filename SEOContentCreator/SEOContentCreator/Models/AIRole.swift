import Foundation
import SwiftData

@Model
final class AIRole {
    var uuid: UUID
    var key: String
    var name: String
    var mandate: String
    var blockKeys: [String]
    var version: Int
    var createdAt: Date
    var updatedAt: Date
    var hasPersonalDefault: Bool = false
    var personalDefaultMandate: String?
    var personalDefaultBlockKeys: [String] = []
    var personalDefaultUpdatedAt: Date?

    init(
        key: String,
        name: String,
        mandate: String,
        blockKeys: [String],
        version: Int = 1
    ) {
        self.uuid = UUID()
        self.key = key
        self.name = name
        self.mandate = mandate
        self.blockKeys = blockKeys
        self.version = version
        self.createdAt = .now
        self.updatedAt = .now
    }
}
