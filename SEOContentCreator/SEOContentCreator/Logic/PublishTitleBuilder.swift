import Foundation

/// Собирает заголовок документа Google Docs из ID темы и её названия.
///
/// Формат: `№[ID] [Тема] — Контент для страницы`.
/// Если ID пустой — префикс `№[ID] ` опускается: `[Тема] — Контент для страницы`.
enum PublishTitleBuilder {
    static let suffix = "Контент для страницы"

    static func title(externalID: String, topicTitle: String) -> String {
        let id = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = topicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = id.isEmpty ? "" : "№\(id) "
        return "\(prefix)\(name) — \(suffix)"
    }
}
