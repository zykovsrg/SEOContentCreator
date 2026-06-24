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

struct FragmentSplicerTests {
    @Test func replacesUniqueFragment() {
        let result = FragmentSplicer.splice(
            fullText: "Начало. Старый кусок. Конец.",
            fragment: "Старый кусок.",
            replacement: "Новый кусок."
        )
        #expect(result == .replaced("Начало. Новый кусок. Конец."))
    }

    @Test func notFoundWhenMissing() {
        let result = FragmentSplicer.splice(
            fullText: "Текст без фрагмента.",
            fragment: "чего тут нет",
            replacement: "X"
        )
        #expect(result == .notFound)
    }

    @Test func notFoundWhenFragmentEmpty() {
        let result = FragmentSplicer.splice(fullText: "Любой текст.", fragment: "", replacement: "X")
        #expect(result == .notFound)
    }

    @Test func ambiguousWhenMultipleMatches() {
        let result = FragmentSplicer.splice(
            fullText: "Повтор. Повтор.",
            fragment: "Повтор.",
            replacement: "X"
        )
        #expect(result == .ambiguous(2))
    }

    @Test func whitespaceSensitiveMatch() {
        // Лишний пробел в искомом фрагменте → совпадения нет.
        let result = FragmentSplicer.splice(
            fullText: "Раз два три.",
            fragment: "Раз  два",
            replacement: "X"
        )
        #expect(result == .notFound)
    }
}

struct FragmentPromptBuilderTests {
    @Test func systemComesFromRoleContext() {
        let prompt = FragmentPromptBuilder().build(
            roleContext: "Ты — ИИ-редактор.",
            instruction: "Упрости.",
            fragment: "Сложный фрагмент."
        )
        #expect(prompt.system == "Ты — ИИ-редактор.")
    }

    @Test func userContainsInstructionAndFragment() {
        let prompt = FragmentPromptBuilder().build(
            roleContext: "роль",
            instruction: "Упрости фрагмент.",
            fragment: "Сложный фрагмент."
        )
        #expect(prompt.user.contains("Упрости фрагмент."))
        #expect(prompt.user.contains("Сложный фрагмент."))
    }

    @Test func userAsksForFragmentOnly() {
        let prompt = FragmentPromptBuilder().build(
            roleContext: "роль",
            instruction: "Упрости.",
            fragment: "Текст."
        )
        #expect(prompt.user.contains("только переписанный фрагмент"))
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
