import Foundation
import SwiftData

enum StageTemplateSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
        let seededStages = Set(existing.map { $0.stageRaw })

        for stage in PipelineStage.allCases where !seededStages.contains(stage.rawValue) {
            let template = makeTemplate(for: stage)
            context.insert(template)
        }
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
