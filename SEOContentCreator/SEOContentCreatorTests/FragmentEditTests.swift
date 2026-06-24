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

@MainActor
struct SkillPresetSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SkillPreset.self, configurations: config)
        return ModelContext(container)
    }

    @Test func seedsDefaultsIntoEmptyStore() throws {
        let context = try makeContext()
        SkillPresetSeeder.seedIfNeeded(in: context)
        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.count == SkillPresetDefaults.all.count)
    }

    @Test func isIdempotent() throws {
        let context = try makeContext()
        SkillPresetSeeder.seedIfNeeded(in: context)
        SkillPresetSeeder.seedIfNeeded(in: context)
        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.count == SkillPresetDefaults.all.count)
    }
}
