import Foundation

enum ImagePromptKind: String, Codable, CaseIterable {
    case cover
    case illustration

    var title: String {
        switch self {
        case .cover:        return "Обложка"
        case .illustration: return "Иллюстрация"
        }
    }
}
