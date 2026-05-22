import Foundation

enum TopicStatus: Equatable {
    case idea
    case ready
    case published

    static func compute(for topic: Topic) -> TopicStatus {
        if topic.publishedAt != nil { return .published }
        if BriefValidation.canStartDraft(title: topic.title, hasDirection: topic.direction != nil) {
            return .ready
        }
        return .idea
    }

    var label: String {
        switch self {
        case .idea:      return "Идея"
        case .ready:     return "Готова к работе"
        case .published: return "Опубликовано"
        }
    }
}
