import Foundation
import SwiftData

@Model
final class StageTemplate {
    var uuid: UUID
    var stageRaw: String
    var articleTypeRaw: String?   // nil = universal (applies to all article types)
    var systemPrompt: String
    var userPromptTemplate: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var templateVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        stage: PipelineStage,
        articleType: ArticleType? = nil,
        systemPrompt: String,
        userPromptTemplate: String,
        modelName: String = "gpt-4.1",
        temperature: Double = 0.6,
        maxTokens: Int = 8000,
        templateVersion: Int = 1
    ) {
        self.uuid = UUID()
        self.stageRaw = stage.rawValue
        self.articleTypeRaw = articleType?.rawValue
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.templateVersion = templateVersion
        self.createdAt = .now
        self.updatedAt = .now
    }

    var stage: PipelineStage? { PipelineStage(rawValue: stageRaw) }
}
