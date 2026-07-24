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
    /// True once the user has finished the review this job's checking-stage remarks
    /// belong to (accepted/rejected everything and pressed "Готово"/"Отклонить всё").
    /// Lets an interrupted review (app closed mid-review) be told apart from a
    /// finished one when restoring on the next launch (FT-20260702-011).
    var reviewResolved: Bool = false
    /// For checking-stage jobs: the article text as it was when this job's remarks
    /// were produced. Accepting remarks re-applies them against this frozen base, so
    /// applying them one at a time (and across an app restart) stays consistent even
    /// though the topic's current version changes underneath. Nil for jobs that
    /// predate this field or are not checking stages.
    var reviewBaseText: String?

    @Relationship var topic: Topic?
    @Relationship(deleteRule: .cascade, inverse: \PersistedRemark.job)
    var persistedRemarks: [PersistedRemark] = []

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
