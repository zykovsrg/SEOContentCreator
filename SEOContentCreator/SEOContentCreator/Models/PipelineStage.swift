import Foundation

enum PipelineStage: String, CaseIterable, Identifiable, Codable {
    case draft
    case productBlocks
    case semanticsInText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft:           return "Черновик"
        case .productBlocks:   return "Продуктовые блоки"
        case .semanticsInText: return "Семантика-в-текст"
        }
    }

    /// All three author stages are run by the ИИ-автор agent (spec §2.14).
    var agentName: String { "ИИ-автор" }
}
