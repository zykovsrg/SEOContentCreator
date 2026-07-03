import Foundation

enum StageProgress {
    /// A stage counts as passed once the topic has at least one accepted
    /// (visible-in-lane) version created for it.
    ///
    /// The "Структура" stage is a special case: it saves straight into
    /// `topic.structureText` instead of creating an `ArticleVersion`, so it
    /// has no version to look up here.
    static func isCompleted(
        _ stage: PipelineStage, versions: [ArticleVersion], structureText: String = "", hasImages: Bool = false
    ) -> Bool {
        if stage == .structure {
            return !structureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if stage == .images {
            return hasImages
        }
        return versions.contains { $0.stageRaw == stage.rawValue && $0.isVisibleInVersionLane }
    }
}
