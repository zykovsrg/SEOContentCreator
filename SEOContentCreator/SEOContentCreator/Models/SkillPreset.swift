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
    /// Stable key linking this preset to its factory default (independent of name).
    /// nil for user-created presets. See SkillPresetDefaults.
    var defaultKey: String?

    init(name: String, prompt: String, roleKey: String, order: Int, defaultKey: String? = nil) {
        self.uuid = UUID()
        self.name = name
        self.prompt = prompt
        self.roleKey = roleKey
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
        self.defaultKey = defaultKey
    }
}
