import Foundation

/// Builds the prompt for regenerating a single remark's `suggestion` after the
/// user adds a free-text comment (e.g. "this is too harsh" or "delete instead").
enum RemarkRedoBuilder {
    static func build(category: String, quote: String, explanation: String, comment: String) -> (system: String, user: String) {
        let user = """
        Ты дорабатываешь одно точечное редакторское замечание к тексту статьи с учётом комментария пользователя.

        Категория: \(category)
        Фрагмент (quote): \(quote)
        Исходное объяснение замечания: \(explanation)
        Комментарий пользователя: \(comment)

        Предложи новую замену для фрагмента с учётом комментария.
        Верни ТОЛЬКО JSON в формате:
        ```json
        {"suggestion":"<новая замена>"}
        ```
        Если по комментарию фрагмент нужно просто удалить, оставь suggestion пустой строкой "".
        """
        return (system: "", user: user)
    }
}
