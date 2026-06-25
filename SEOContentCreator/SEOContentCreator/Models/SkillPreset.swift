import Foundation
import SwiftData

@Model
final class SkillPreset {
    var uuid: UUID
    var name: String
    var prompt: String
    /// AIRole.key: "author" / "seo" / "factChecker" / "editor".
    var roleKey: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(name: String, prompt: String, roleKey: String, order: Int) {
        self.uuid = UUID()
        self.name = name
        self.prompt = prompt
        self.roleKey = roleKey
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
