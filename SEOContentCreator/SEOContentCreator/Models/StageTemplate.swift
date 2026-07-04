import Foundation
import SwiftData

@Model
final class StageTemplate {
    var uuid: UUID
    var stageRaw: String
    var articleTypeRaw: String?   // nil = universal (applies to all article types)
    var userPromptTemplate: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    /// Reasoning intensity for GPT-5.x / o-series models ("low"/"medium"/"high").
    /// nil = do not send the parameter (model default). Ignored for legacy models.
    var reasoningEffort: String?
    var templateVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        stage: PipelineStage,
        articleType: ArticleType? = nil,
        userPromptTemplate: String,
        modelName: String = "gpt-4.1",
        temperature: Double = 0.6,
        maxTokens: Int = 8000,
        reasoningEffort: String? = nil,
        templateVersion: Int = 1
    ) {
        self.uuid = UUID()
        self.stageRaw = stage.rawValue
        self.articleTypeRaw = articleType?.rawValue
        self.userPromptTemplate = userPromptTemplate
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.reasoningEffort = reasoningEffort
        self.templateVersion = templateVersion
        self.createdAt = .now
        self.updatedAt = .now
    }

    var stage: PipelineStage? { PipelineStage(rawValue: stageRaw) }
}
