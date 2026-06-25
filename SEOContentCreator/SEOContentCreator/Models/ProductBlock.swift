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

    init(name: String, prompt: String, order: Int) {
        self.uuid = UUID()
        self.name = name
        self.prompt = prompt
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
