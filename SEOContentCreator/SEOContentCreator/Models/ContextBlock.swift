import Foundation
import SwiftData

@Model
final class ContextBlock {
    var uuid: UUID
    var key: String
    var title: String
    var text: String
    var version: Int
    var createdAt: Date
    var updatedAt: Date
    var hasPersonalDefault: Bool = false
    var personalDefaultText: String?
    var personalDefaultUpdatedAt: Date?

    init(
        key: String,
        title: String,
        text: String,
        version: Int = 1
    ) {
        self.uuid = UUID()
        self.key = key
        self.title = title
        self.text = text
        self.version = version
        self.createdAt = .now
        self.updatedAt = .now
    }
}
