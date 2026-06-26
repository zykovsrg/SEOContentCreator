import Foundation
import SwiftData

@Model
final class ProductBlock {
    var uuid: UUID
    var name: String
    var prompt: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date
    /// Stable key linking this block to its factory default (independent of name).
    /// nil for user-created blocks. See ProductBlockDefaults.
    var defaultKey: String?

    init(name: String, prompt: String, order: Int, defaultKey: String? = nil) {
        self.uuid = UUID()
        self.name = name
        self.prompt = prompt
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
        self.defaultKey = defaultKey
    }
}
