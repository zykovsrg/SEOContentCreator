import Foundation

enum VersionSource: String, Codable {
    case generated
    case manualEdit
    case acceptedFull
    case acceptedPartial
    case rollback
    case importFromDocs
    case checkApplied
    case skillApplied
    case fragmentRegenerated

    var title: String {
        switch self {
        case .generated:       return "Сгенерировано"
        case .manualEdit:      return "Ручная правка"
        case .acceptedFull:    return "Принято целиком"
        case .acceptedPartial: return "Принято частично"
        case .rollback:        return "Откат"
        case .importFromDocs:  return "Импорт из Docs"
        case .checkApplied:        return "Правки проверки"
        case .skillApplied:        return "Правка скиллом"
        case .fragmentRegenerated: return "Регенерация фрагмента"
        }
    }
}
