import Testing
import SwiftData
@testable import SEOContentCreator

struct VersionSourceFragmentTests {
    @Test func skillAppliedTitle() {
        #expect(VersionSource.skillApplied.title == "Правка скиллом")
    }

    @Test func fragmentRegeneratedTitle() {
        #expect(VersionSource.fragmentRegenerated.title == "Регенерация фрагмента")
    }
}

struct SkillPresetDefaultsTests {
    @Test func providesFourStarterSkills() {
        #expect(SkillPresetDefaults.all.count == 4)
    }

    @Test func everyDefaultHasNamePromptAndKnownRole() {
        let knownRoles: Set<String> = ["author", "seo", "factChecker", "editor"]
        for preset in SkillPresetDefaults.all {
            #expect(!preset.name.isEmpty)
            #expect(!preset.prompt.isEmpty)
            #expect(knownRoles.contains(preset.roleKey))
        }
    }

    @Test func makeAllAssignsIncreasingOrder() {
        let presets = SkillPresetDefaults.makeAll()
        #expect(presets.map(\.order) == Array(0..<presets.count))
    }
}
