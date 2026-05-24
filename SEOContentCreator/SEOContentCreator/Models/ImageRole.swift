import Foundation

enum ImageRole: String, Codable {
    case cover
    case illustration

    var title: String {
        switch self {
        case .cover:        return "Обложка"
        case .illustration: return "Иллюстрация"
        }
    }
}
