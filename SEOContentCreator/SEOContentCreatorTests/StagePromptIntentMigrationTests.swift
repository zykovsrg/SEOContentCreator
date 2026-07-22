import Testing
import Foundation
@testable import SEOContentCreator

struct StagePromptIntentMigrationTests {
    @Test func upgradesCustomizedStructureWithoutReplacingExistingText() {
        let original = "Мой изменённый промт структуры. Верни Markdown."
        let upgraded = StagePromptIntentMigration.upgrade(original, for: .structure)
        #expect(upgraded.contains(original))
        #expect(upgraded.contains("{{задача_читателя}}"))
        #expect(upgraded.contains("{{семантика}}"))
    }

    @Test func upgradeIsIdempotent() {
        let first = StagePromptIntentMigration.upgrade("Мой промт", for: .seoCheck)
        let second = StagePromptIntentMigration.upgrade(first, for: .seoCheck)
        #expect(second == first)
        #expect(second.components(separatedBy: "{{задача_читателя}}").count == 2)
    }

    @Test func unrelatedStageIsUnchanged() {
        #expect(StagePromptIntentMigration.upgrade("Фактчек", for: .factCheck) == "Фактчек")
    }
}
