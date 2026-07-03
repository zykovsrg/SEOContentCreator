import Foundation

enum StageKind {
    case author
    case checking
    /// A normal chat-completion stage, but its result is a list of prompt-improvement
    /// recommendations (`PromptRecommendation`), not article remarks or a new version.
    case analysis
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
    case promptAnalysis

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
        case .promptAnalysis:  return "Анализ и обучение"
        }
    }

    var kind: StageKind {
        switch self {
        case .structure, .draft, .productBlocks, .semanticsInText: return .author
        case .seoCheck, .factCheck, .finalReview:      return .checking
        case .images: return .action
        case .promptAnalysis: return .analysis
        }
    }

    var agentName: String {
        switch self {
        case .structure, .draft, .productBlocks, .semanticsInText: return "ИИ-автор"
        case .seoCheck:    return "ИИ-SEO"
        case .factCheck:   return "ИИ-фактчекер"
        case .finalReview: return "ИИ-редактор"
        case .images:      return "Генератор изображений"
        case .promptAnalysis: return "ИИ-аналитик"
        }
    }

    var roleKey: String {
        switch self {
        case .structure, .draft, .productBlocks, .semanticsInText: return "author"
        case .seoCheck:    return "seo"
        case .factCheck:   return "factChecker"
        case .finalReview: return "editor"
        case .images:      return "images"
        case .promptAnalysis: return "analyst"
        }
    }
}
