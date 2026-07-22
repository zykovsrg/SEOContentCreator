import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct TemplatesMigrationV3Tests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StageTemplate.self, ContextBlock.self, AIRole.self,
                 ImagePromptTemplate.self, ImageStylePreset.self, SkillPreset.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TemplatesMigrationV3Tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func preservesCustomizedTemplatesRolesAndBlocksAsPersonalDefaults() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let oldDraft = StageTemplate(
            stage: .draft,
            userPromptTemplate: "старый user"
        )
        let oldProductBlocks = StageTemplate(
            stage: .productBlocks,
            userPromptTemplate: "правленный productBlocks"
        )
        context.insert(oldDraft)
        context.insert(oldProductBlocks)
        context.insert(ContextBlock(key: "editorialPolicy", title: "Редполитика", text: "старая редполитика"))
        context.insert(AIRole(
            key: "author",
            name: "ИИ-автор",
            mandate: "старый mandate",
            blockKeys: ["editorialPolicy", "sources"]
        ))

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        // draft is one of the 4 reader-intent stages: original custom text is preserved,
        // and the reader-intent addition is appended (no anchor match on this short custom text).
        #expect(oldDraft.userPromptTemplate.contains("старый user"))
        #expect(oldDraft.userPromptTemplate.contains("{{задача_читателя}}"))
        #expect(oldDraft.hasPersonalDefault)
        #expect(oldDraft.personalDefaultUserPromptTemplate == oldDraft.userPromptTemplate)

        // productBlocks is not one of the 4 reader-intent stages: fully unchanged by the upgrade,
        // but still becomes its first personal-default snapshot.
        #expect(oldProductBlocks.userPromptTemplate == "правленный productBlocks")
        #expect(oldProductBlocks.hasPersonalDefault)
        #expect(oldProductBlocks.personalDefaultUserPromptTemplate == "правленный productBlocks")

        // The unconditional block/role-mandate overwrite loop is removed in Task 5:
        // the old custom text is preserved, not replaced with factory text.
        let blocks = try context.fetch(FetchDescriptor<ContextBlock>())
        let policy = blocks.first { $0.key == "editorialPolicy" }
        #expect(policy?.text == "старая редполитика")
        #expect(policy?.hasPersonalDefault == true)
        #expect(policy?.personalDefaultText == "старая редполитика")

        let roles = try context.fetch(FetchDescriptor<AIRole>())
        let author = roles.first { $0.key == "author" }
        #expect(author?.mandate == "старый mandate")
        #expect(author?.hasPersonalDefault == true)
        #expect(author?.personalDefaultMandate == "старый mandate")
    }

    @Test func addsShortenPresetForExistingInstalls() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        context.insert(SkillPreset(name: "Мой скилл", prompt: "x", roleKey: "editor", order: 0))

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.contains { $0.defaultKey == "shorten" })
        #expect(presets.contains { $0.name == "Мой скилл" })
    }

    @Test func doesNotCreateSingleShortenPresetOnFreshInstall() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.isEmpty)
    }

    // Renamed from seoCheckMigratesInVersion4ToIncludeSEOMeta: Task 5 removes the
    // unconditional cascade overwrite that used to guarantee old seoCheck prompts
    // (from before the {{текущий_h1}} field existed) got fully replaced with the
    // current factory text. That full-replacement guarantee is exactly what this
    // task eliminates — old customized seoCheck text is now preserved and only
    // gets the reader-intent addition, not a rewrite to add {{текущий_h1}}.
    @Test func seoCheckPreservesOldTextAndAddsReaderIntentAddition() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let oldSeoCheck = StageTemplate(
            stage: .seoCheck,
            userPromptTemplate: "старый seoCheck без H1"
        )
        context.insert(oldSeoCheck)

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(oldSeoCheck.userPromptTemplate.contains("старый seoCheck без H1"))
        #expect(oldSeoCheck.userPromptTemplate.contains("{{задача_читателя}}"))
        #expect(oldSeoCheck.hasPersonalDefault)
        #expect(oldSeoCheck.personalDefaultUserPromptTemplate == oldSeoCheck.userPromptTemplate)
    }

    @Test func checkingStagesGetLoweredTemperatureInVersion5() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let oldSeoCheck = StageTemplate(stage: .seoCheck, userPromptTemplate: "x", temperature: 0.6)
        let oldFactCheck = StageTemplate(stage: .factCheck, userPromptTemplate: "x", temperature: 0.6)
        let oldFinalReview = StageTemplate(stage: .finalReview, userPromptTemplate: "x", temperature: 0.6)
        let oldDraft = StageTemplate(stage: .draft, userPromptTemplate: "x", temperature: 0.6)
        context.insert(oldSeoCheck)
        context.insert(oldFactCheck)
        context.insert(oldFinalReview)
        context.insert(oldDraft)

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(oldSeoCheck.temperature == 0.3)
        #expect(oldFactCheck.temperature == 0.3)
        #expect(oldFinalReview.temperature == 0.3)
        #expect(oldDraft.temperature == 0.6)
    }

    @Test func migrationRunsOnce() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        let draft = try context.fetch(FetchDescriptor<StageTemplate>())
            .first { $0.stageRaw == PipelineStage.draft.rawValue }
        draft?.userPromptTemplate = "правка пользователя после миграции"

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(draft?.userPromptTemplate == "правка пользователя после миграции")
    }

    @Test func addsReaderWorldPresetForExistingInstallsWithoutIt() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        context.insert(SkillPreset(name: "Мой скилл", prompt: "x", roleKey: "editor", order: 0))

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.contains { $0.defaultKey == "readerWorld" })
    }

    @Test func doesNotDuplicateManuallyCreatedReaderWorldPreset() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        // Created by hand in the app before it became a factory default:
        // same name, defaultKey still nil until SkillPresetSeeder backfills it.
        context.insert(SkillPreset(name: "Мир читателя", prompt: "x", roleKey: "editor", order: 0))

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.filter { $0.name == "Мир читателя" }.count == 1)
    }

    @Test func imagePromptTemplatesAreRefreshedToDefaults() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let oldCover = ImagePromptTemplate(kind: .cover, userPromptTemplate: "старый промт обложки")
        context.insert(oldCover)

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(oldCover.userPromptTemplate == ImagePromptDefaults.content(for: .cover))
    }
}
