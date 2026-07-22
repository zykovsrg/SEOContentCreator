import Foundation

/// Upgrades a stored (possibly user-customized) stage prompt in place to add
/// the reader-intent instructions, without ever replacing the rest of the
/// text. Used by `StageTemplateSeeder.migrateTemplatesIfNeeded` so that
/// existing installs get the new instructions additively instead of having
/// their customized prompt wholesale overwritten with the factory default.
enum StagePromptIntentMigration {
    static func upgrade(_ text: String, for stage: PipelineStage) -> String {
        guard let addition = addition(for: stage) else { return text }
        let marker = "<!-- reader-intent-v1:\(stage.rawValue) -->"
        guard !text.contains(marker) else { return text }
        return insertAtKnownAnchor(text, addition: addition, stage: stage)
            ?? text + "\n\n" + addition
    }

    private static func addition(for stage: PipelineStage) -> String? {
        switch stage {
        case .structure:
            return """
            <!-- reader-intent-v1:structure -->
            {{задача_читателя}}

            Поисковые запросы — ориентир для понимания вопросов и контекста читателя, а не список обязательных заголовков или точных фраз:
            {{семантика}}

            Используй выбранное семантическое покрытие как проверку полноты, но не превращай названия категорий в обязательные разделы. Верни только структуру H1/H2/H3 с пометками; карту задачи в результат не включай.
            """
        case .draft:
            return """
            <!-- reader-intent-v1:draft -->
            {{задача_читателя}}

            Используй карту как рамку текста: каждый раздел помогает достичь критерия полезного ответа или снять значимый барьер. Саму карту в статью не включай.
            """
        case .semanticsInText:
            return """
            <!-- reader-intent-v1:semanticsInText -->
            {{задача_читателя}}

            H1, Title и Description должны отражать практическую задачу читателя без неподтверждённых обещаний.
            """
        case .seoCheck:
            return """
            <!-- reader-intent-v1:seoCheck -->
            {{задача_читателя}}

            Проверь, отвечает ли страница практическому интенту и покрывает ли выбранные в карте типы информации. Не требуй категории, которые в карте не выбраны. Для замечаний по этим критериям используй категории «Интент» и «Полнота».
            """
        default:
            return nil
        }
    }

    private static func insertAtKnownAnchor(
        _ text: String,
        addition: String,
        stage: PipelineStage
    ) -> String? {
        let anchor: String
        switch stage {
        case .structure:
            anchor = "Не добавляй ключевые запросы. Формат — Markdown."
        case .draft:
            anchor = "{{структура}}"
        case .semanticsInText:
            anchor = "Текущий текст:"
        case .seoCheck:
            anchor = "Текст:"
        default:
            return nil
        }
        guard let range = text.range(of: anchor) else { return nil }
        return String(text[..<range.upperBound]) + "\n\n" + addition + String(text[range.upperBound...])
    }
}
