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

    @Relationship var topic: Topic?

    init(stage: PipelineStage, agentName: String, modelName: String) {
        self.uuid = UUID()
        self.stageRaw = stage.rawValue
        self.agentName = agentName
        self.modelName = modelName
        self.statusRaw = JobStatus.running.rawValue
        self.startedAt = .now
    }

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }

    var stageTitle: String { PipelineStage(rawValue: stageRaw)?.title ?? stageRaw }
}
