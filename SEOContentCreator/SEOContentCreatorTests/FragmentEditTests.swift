import Testing
import SwiftData
import Foundation
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
    @Test func providesStarterSkillsIncludingShortenAndReaderWorld() {
        #expect(SkillPresetDefaults.all.count == 6)
        #expect(SkillPresetDefaults.all.contains { $0.key == "shorten" })
        #expect(SkillPresetDefaults.all.contains { $0.key == "readerWorld" })
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
struct FragmentEditorTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Topic.self, ReaderIntent.self, PromptRecommendation.self, ArticleVersion.self, GenerationJob.self, PersistedRemark.self,
            AIRole.self, ContextBlock.self, SkillPreset.self, SemanticKeyword.self, PublishedSitePage.self,
            configurations: config
        )
    }

    private func tokenStream(_ text: String) -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.token(text))
                continuation.yield(.finish(reason: "stop"))
                continuation.finish()
            }
        }
    }

    private func errorStream() -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "test", code: 1))
            }
        }
    }

    @Test func successProducesRewrittenFragment() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        context.insert(topic)

        let editor = FragmentEditor(streamProvider: tokenStream("  Новый кусок.  "), keyProvider: { "key" })
        await editor.run(
            fragment: "Старый кусок.",
            instruction: "Упрости.",
            roleKey: "editor",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 4000,
            source: .skillApplied,
            topic: topic,
            in: context
        )

        // Trimmed — leading/trailing whitespace from the model's raw output is stripped.
        #expect(editor.rewrittenFragment == "Новый кусок.")
        #expect(editor.lastErrorMessage == nil)

        let jobs = try context.fetch(FetchDescriptor<GenerationJob>())
        #expect(jobs.count == 1)
        #expect(jobs.first?.status == .success)
    }

    @Test func errorPathSurfacesMessageAndNoRewrittenFragment() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        context.insert(topic)

        let editor = FragmentEditor(streamProvider: errorStream(), keyProvider: { "key" })
        await editor.run(
            fragment: "Кусок.",
            instruction: "Упрости.",
            roleKey: "author",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 4000,
            source: .fragmentRegenerated,
            topic: topic,
            in: context
        )

        #expect(editor.rewrittenFragment == nil)
        #expect(editor.lastErrorMessage != nil)
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

    @Test func seedsAssignDefaultKeys() throws {
        let context = try makeContext()
        SkillPresetSeeder.seedIfNeeded(in: context)
        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        let keys = Set(presets.compactMap { $0.defaultKey })
        #expect(keys == Set(SkillPresetDefaults.all.map { $0.key }))
    }

    @Test func backfillAssignsKeyToLegacyPresetByName() throws {
        let context = try makeContext()
        // Simulate an install seeded before defaultKey existed.
        let def = SkillPresetDefaults.all[0]
        let legacy = SkillPreset(name: def.name, prompt: def.prompt, roleKey: def.roleKey, order: 0)
        legacy.defaultKey = nil
        context.insert(legacy)

        SkillPresetSeeder.seedIfNeeded(in: context)

        #expect(legacy.defaultKey == def.key)
    }

    @Test func resetMatchesByKeyAfterRename() throws {
        let context = try makeContext()
        SkillPresetSeeder.seedIfNeeded(in: context)
        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        guard let preset = presets.first else { #expect(Bool(false)); return }

        let originalKey = preset.defaultKey
        preset.name = "Переименовал как угодно"

        // The editor matches the factory default by key, not name.
        let matched = SkillPresetDefaults.all.first { $0.key == preset.defaultKey }
        #expect(matched != nil)
        #expect(matched?.key == originalKey)
    }
}
