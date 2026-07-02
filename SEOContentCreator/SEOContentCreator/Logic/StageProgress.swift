import Foundation

enum StageProgress {
    /// A stage counts as passed once the topic has at least one accepted
    /// (visible-in-lane) version created for it.
    static func isCompleted(_ stage: PipelineStage, versions: [ArticleVersion]) -> Bool {
        versions.contains { $0.stageRaw == stage.rawValue && $0.isVisibleInVersionLane }
    }
}
