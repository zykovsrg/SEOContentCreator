import Foundation

enum StageKind {
    case author
    case checking
    /// Not a chat-completion stage: no `StageTemplate` is seeded for it, and
    /// running it opens a dedicated screen instead of calling `StageExecutor`.
    case action
}

enum PipelineStage: String, CaseIterable, Identifiable, Codable {
    case structure
    case draft
    case productBlocks
    case semanticsInText
    case seoCheck
    case factCheck
    case finalReview
    case images

    var id: String { rawValue }

    var title: String {
        switch self {
        case .structure:       return "Структура"
        case .draft:           return "Черновик"
        case .productBlocks:   return "Продуктовые блоки"
        case .semanticsInText: return "Семантика-в-текст"
        case .seoCheck:        return "Проверка SEO"
        case .factCheck:       return "Фактчекинг"
        case .finalReview:     return "Финальная вычитка"
        case .images:          return "Изображения"
        }
    }

    var kind: StageKind {
        switch self {
        case .structure, .draft, .productBlocks, .semanticsInText: return .author
        case .seoCheck, .factCheck, .finalReview:      return .checking
        case .images: return .action
        }
    }

    var agentName: String {
        switch self {
        case .structure, .draft, .productBlocks, .semanticsInText: return "ИИ-автор"
        case .seoCheck:    return "ИИ-SEO"
        case .factCheck:   return "ИИ-фактчекер"
        case .finalReview: return "ИИ-редактор"
        case .images:      return "Генератор изображений"
        }
    }

    var roleKey: String {
        switch self {
        case .structure, .draft, .productBlocks, .semanticsInText: return "author"
        case .seoCheck:    return "seo"
        case .factCheck:   return "factChecker"
        case .finalReview: return "editor"
        case .images:      return "images"
        }
    }
}
