import Foundation
import SwiftData

enum StageTemplateSeeder {
    static let templatesDefaultsVersionKey = "templatesDefaultsVersion"
    private static let currentTemplatesDefaultsVersion = 2

    @MainActor
    static func seedIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        seedStageTemplatesIfNeeded(in: context)
        seedContextBlocksIfNeeded(in: context)
        seedRolesIfNeeded(in: context)
        seedImagePromptTemplatesIfNeeded(in: context)
        seedImageStylePresetIfNeeded(in: context)
        migrateStageTemplateSystemPromptsIfNeeded(in: context, defaults: defaults)
    }

    @MainActor
    private static func seedStageTemplatesIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
        let seededStages = Set(existing.map { $0.stageRaw })

        for stage in PipelineStage.allCases where !seededStages.contains(stage.rawValue) {
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
        context.insert(ImageStylePresetDefaults.makeDefault())
    }

    @MainActor
    private static func migrateStageTemplateSystemPromptsIfNeeded(
        in context: ModelContext,
        defaults: UserDefaults
    ) {
        let storedVersion = defaults.integer(forKey: templatesDefaultsVersionKey)
        guard storedVersion < currentTemplatesDefaultsVersion else { return }

        let templates = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
        for template in templates {
            guard let stage = template.stage else { continue }
            template.systemPrompt = StageTemplateDefaults.content(for: stage).systemPrompt
            template.updatedAt = .now
        }
        defaults.set(currentTemplatesDefaultsVersion, forKey: templatesDefaultsVersionKey)
    }

    private static func makeTemplate(for stage: PipelineStage) -> StageTemplate {
        let c = StageTemplateDefaults.content(for: stage)
        return StageTemplate(
            stage: stage,
            systemPrompt: c.systemPrompt,
            userPromptTemplate: c.userPromptTemplate,
            modelName: c.modelName,
            temperature: c.temperature,
            maxTokens: c.maxTokens
        )
    }
}
