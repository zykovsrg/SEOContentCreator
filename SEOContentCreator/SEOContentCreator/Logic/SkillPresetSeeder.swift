import Foundation
import SwiftData

enum SkillPresetSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<SkillPreset>())) ?? []
        if existing.isEmpty {
            for preset in SkillPresetDefaults.makeAll() {
                context.insert(preset)
            }
            return
        }
        backfillDefaultKeys(existing)
    }

    /// One-time migration for installs seeded before `defaultKey` existed:
    /// match each keyless preset to its factory default by name and assign the key.
    /// After this, renaming the preset no longer breaks "reset to default".
    @MainActor
    static func backfillDefaultKeys(_ presets: [SkillPreset]) {
        for preset in presets where preset.defaultKey == nil {
            if let def = SkillPresetDefaults.all.first(where: { $0.name == preset.name }) {
                preset.defaultKey = def.key
            }
        }
    }
}
