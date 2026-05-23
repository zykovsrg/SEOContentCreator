import Foundation

enum StageKind {
    case author
    case checking
}

enum PipelineStage: String, CaseIterable, Identifiable, Codable {
    case draft
    case productBlocks
    case semanticsInText
    case seoCheck
    case factCheck
    case finalReview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft:           return "Черновик"
        case .productBlocks:   return "Продуктовые блоки"
        case .semanticsInText: return "Семантика-в-текст"
        case .seoCheck:        return "Проверка SEO"
        case .factCheck:       return "Фактчекинг"
        case .finalReview:     return "Финальная вычитка"
        }
    }

    var kind: StageKind {
        switch self {
        case .draft, .productBlocks, .semanticsInText: return .author
        case .seoCheck, .factCheck, .finalReview:      return .checking
        }
    }

    var agentName: String {
        switch self {
        case .draft, .productBlocks, .semanticsInText: return "ИИ-автор"
        case .seoCheck:    return "ИИ-SEO"
        case .factCheck:   return "ИИ-фактчекер"
        case .finalReview: return "ИИ-редактор"
        }
    }

    var roleKey: String {
        switch self {
        case .draft, .productBlocks, .semanticsInText: return "author"
        case .seoCheck:    return "seo"
        case .factCheck:   return "factChecker"
        case .finalReview: return "editor"
        }
    }
}
