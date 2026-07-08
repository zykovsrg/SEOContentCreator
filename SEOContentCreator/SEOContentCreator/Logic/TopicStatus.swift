import Foundation

enum TopicStatus: Equatable {
    case brief
    case inProgress(PipelineStage)
    case done
    case published

    static func compute(for topic: Topic) -> TopicStatus {
        if topic.publishedAt != nil { return .published }
        let hasImages = !topic.images.filter { !$0.isArchived }.isEmpty
        let hasPromptRecommendations = !topic.promptRecommendations.isEmpty
        let completed = StagePipeline.completedCount { stage in
            StageProgress.isCompleted(
                stage,
                versions: topic.versions,
                structureText: topic.structureText,
                hasImages: hasImages,
                hasPromptRecommendations: hasPromptRecommendations
            )
        }
        if completed == StagePipeline.workflow.count { return .done }
        guard completed > 0,
              let next = StagePipeline.nextStage(isCompleted: { stage in
                  StageProgress.isCompleted(
                      stage,
                      versions: topic.versions,
                      structureText: topic.structureText,
                      hasImages: hasImages,
                      hasPromptRecommendations: hasPromptRecommendations
                  )
              })
        else {
            return .brief
        }
        return .inProgress(next)
    }

    var label: String {
        switch self {
        case .brief:             return "Бриф"
        case .inProgress(let s): return s.title
        case .done:              return "Готово"
        case .published: return "Опубликовано"
        }
    }
}
