import Foundation

enum ArticleType: String, CaseIterable, Identifiable, Codable {
    case disease
    case service
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disease: return "Заболевание"
        case .service:  return "Услуга"
        case .info:     return "Информационная"
        }
    }
}
