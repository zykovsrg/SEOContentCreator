import Foundation
import SwiftData

@Model
final class GenerationJob {
    var uuid: UUID
    var stageRaw: String
    var agentName: String
    var modelName: String
    var statusRaw: String
    var startedAt: Date
    var finishedAt: Date?
    var errorMessage: String?
    var resultVersionID: UUID?
    /// Token usage for this run, filled from OpenAI's `stream_options.include_usage`
    /// event. Nil for jobs that predate this field or ran without it (e.g. errored
    /// before the usage chunk arrived).
    var promptTokens: Int?
    var completionTokens: Int?

    @Relationship var topic: Topic?

    init(stageLabel: String, agentName: String, modelName: String) {
        self.uuid = UUID()
        self.stageRaw = stageLabel
        self.agentName = agentName
        self.modelName = modelName
        self.statusRaw = JobStatus.running.rawValue
        self.startedAt = .now
    }

    convenience init(stage: PipelineStage, agentName: String, modelName: String) {
        self.init(stageLabel: stage.rawValue, agentName: agentName, modelName: modelName)
    }

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }

    var stageTitle: String {
        if let stage = PipelineStage(rawValue: stageRaw) { return stage.title }
        if stageRaw == "image" { return "Изображение" }
        return stageRaw
    }
}
