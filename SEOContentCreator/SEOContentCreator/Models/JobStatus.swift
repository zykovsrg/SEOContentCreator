import Foundation

enum JobStatus: String, Codable {
    case running
    case success
    case error
    case cancelled

    var title: String {
        switch self {
        case .running:   return "Выполняется"
        case .success:   return "Успех"
        case .error:     return "Ошибка"
        case .cancelled: return "Отменён"
        }
    }
}
