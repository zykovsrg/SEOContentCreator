import Foundation

enum NodeType: String, CaseIterable, Identifiable, Codable {
    case direction
    case doctor
    case advantage
    case fact
    case source
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direction: return "Направление"
        case .doctor:    return "Врач"
        case .advantage: return "Преимущество"
        case .fact:      return "Факт"
        case .source:    return "Источник"
        case .folder:    return "Раздел"
        }
    }
}
