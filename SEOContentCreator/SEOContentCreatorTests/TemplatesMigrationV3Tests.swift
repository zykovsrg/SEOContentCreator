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

    @Test func overwritesCascadeTemplatesAndBlocks() throws {
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

        #expect(oldDraft.userPromptTemplate == StageTemplateDefaults.content(for: .draft).userPromptTemplate)
        #expect(oldProductBlocks.userPromptTemplate == StageTemplateDefaults.content(for: .productBlocks).userPromptTemplate)

        let blocks = try context.fetch(FetchDescriptor<ContextBlock>())
        let policy = blocks.first { $0.key == "editorialPolicy" }
        #expect(policy?.text.contains("Один абзац") == true)

        let roles = try context.fetch(FetchDescriptor<AIRole>())
        let author = roles.first { $0.key == "author" }
        #expect(author?.mandate.contains("Т—Ж") == true)
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

    @Test func seoCheckMigratesInVersion4ToIncludeSEOMeta() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let oldSeoCheck = StageTemplate(
            stage: .seoCheck,
            userPromptTemplate: "старый seoCheck без H1"
        )
        context.insert(oldSeoCheck)

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(oldSeoCheck.userPromptTemplate.contains("{{текущий_h1}}"))
        #expect(oldSeoCheck.userPromptTemplate == StageTemplateDefaults.content(for: .seoCheck).userPromptTemplate)
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
