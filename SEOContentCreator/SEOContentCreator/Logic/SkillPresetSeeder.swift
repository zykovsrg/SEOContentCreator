import Foundation
import SwiftData

enum SkillPresetSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<SkillPreset>())) ?? []
        guard existing.isEmpty else { return }
        for preset in SkillPresetDefaults.makeAll() {
            context.insert(preset)
        }
    }
}
