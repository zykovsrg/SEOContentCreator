import Foundation
import SwiftData

enum StageTemplateSeeder {
    static let templatesDefaultsVersionKey = "templatesDefaultsVersion"
    private static let currentTemplatesDefaultsVersion = 7

    @MainActor
    static func seedIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        seedStageTemplatesIfNeeded(in: context)
        seedContextBlocksIfNeeded(in: context)
        seedRolesIfNeeded(in: context)
        seedImagePromptTemplatesIfNeeded(in: context)
        seedImageStylePresetIfNeeded(in: context)
        migrateTemplatesIfNeeded(in: context, defaults: defaults)
    }

    @MainActor
    private static func seedStageTemplatesIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
        let seededStages = Set(existing.map { $0.stageRaw })

        for stage in PipelineStage.allCases where stage.kind != .action && !seededStages.contains(stage.rawValue) {
            let template = makeTemplate(for: stage)
            context.insert(template)
        }
    }

    @MainActor
    private static func seedContextBlocksIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ContextBlock>())) ?? []
        guard existing.isEmpty else { return }

        for item in ContextBlockDefaults.all {
            context.insert(ContextBlock(key: item.key, title: item.title, text: item.text))
        }
    }

    @MainActor
    private static func seedRolesIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AIRole>())) ?? []
        guard existing.isEmpty else { return }

        for item in RoleDefaults.all {
            context.insert(AIRole(
                key: item.key,
                name: item.name,
                mandate: item.mandate,
                blockKeys: item.blockKeys
            ))
        }
    }

    @MainActor
    private static func seedImagePromptTemplatesIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ImagePromptTemplate>())) ?? []
        let seeded = Set(existing.map { $0.kindRaw })
        for kind in ImagePromptKind.allCases where !seeded.contains(kind.rawValue) {
            context.insert(ImagePromptTemplate(kind: kind, userPromptTemplate: ImagePromptDefaults.content(for: kind)))
        }
    }

    @MainActor
    private static func seedImageStylePresetIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ImageStylePreset>())) ?? []
        guard existing.isEmpty else { return }
        for preset in ImageStylePresetDefaults.makeDefaults() {
            context.insert(preset)
        }
    }

    @MainActor
    private static func migrateTemplatesIfNeeded(
        in context: ModelContext,
        defaults: UserDefaults
    ) {
        let storedVersion = defaults.integer(forKey: templatesDefaultsVersionKey)
        guard storedVersion < currentTemplatesDefaultsVersion else { return }

        let cascadeStages: Set<String> = [
            PipelineStage.structure.rawValue,
            PipelineStage.draft.rawValue,
            PipelineStage.factCheck.rawValue,
            PipelineStage.finalReview.rawValue,
            PipelineStage.seoCheck.rawValue
        ]
        let templates = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
        for template in templates {
            guard let stage = template.stage, cascadeStages.contains(template.stageRaw) else { continue }
            let content = StageTemplateDefaults.content(for: stage)
            template.userPromptTemplate = content.userPromptTemplate
            // Checking stages need a low, predictable temperature (stable JSON,
            // less "creativity"); author stages keep their existing temperature.
            if stage.kind == .checking {
                template.temperature = content.temperature
            }
            template.updatedAt = .now
        }

        let migratedBlockKeys: Set<String> = ["editorialPolicy", "sources"]
        let blocks = (try? context.fetch(FetchDescriptor<ContextBlock>())) ?? []
        for block in blocks where migratedBlockKeys.contains(block.key) {
            if let def = ContextBlockDefaults.defaultForKey(block.key) {
                block.text = def.text
            }
        }

        let roles = (try? context.fetch(FetchDescriptor<AIRole>())) ?? []
        if let author = roles.first(where: { $0.key == "author" }),
           let def = RoleDefaults.defaultForKey("author") {
            author.mandate = def.mandate
        }
        if !roles.isEmpty, !roles.contains(where: { $0.key == "analyst" }),
           let def = RoleDefaults.defaultForKey("analyst") {
            context.insert(AIRole(key: def.key, name: def.name, mandate: def.mandate, blockKeys: def.blockKeys))
        }

        let presets = (try? context.fetch(FetchDescriptor<SkillPreset>())) ?? []
        if !presets.isEmpty,
           !presets.contains(where: { $0.defaultKey == "shorten" }),
           let def = SkillPresetDefaults.all.first(where: { $0.key == "shorten" }) {
            let nextOrder = (presets.map(\.order).max() ?? -1) + 1
            context.insert(SkillPresetDefaults.make(def, order: nextOrder))
        }

        // ImageStylePreset seeds only when the whole table is empty (seedImageStylePresetIfNeeded),
        // so installs that already have a preset never get new named defaults without this step.
        let stylePresets = (try? context.fetch(FetchDescriptor<ImageStylePreset>())) ?? []
        let existingStylePresetNames = Set(stylePresets.map(\.name))
        for def in ImageStylePresetDefaults.all where !existingStylePresetNames.contains(def.name) {
            context.insert(ImageStylePreset(name: def.name, styleText: def.styleText, size: def.size))
        }
        defaults.set(currentTemplatesDefaultsVersion, forKey: templatesDefaultsVersionKey)
    }

    private static func makeTemplate(for stage: PipelineStage) -> StageTemplate {
        let c = StageTemplateDefaults.content(for: stage)
        return StageTemplate(
            stage: stage,
            userPromptTemplate: c.userPromptTemplate,
            modelName: c.modelName,
            temperature: c.temperature,
            maxTokens: c.maxTokens
        )
    }
}
