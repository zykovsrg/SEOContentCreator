import Foundation
import SwiftData

/// A question word the seed planner may combine with the topic.
@Model
final class SemanticQueryMask {
    var uuid: UUID
    var text: String
    var isEnabled: Bool
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(text: String, order: Int, isEnabled: Bool = true) {
        self.uuid = UUID()
        self.text = text
        self.isEnabled = isEnabled
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
