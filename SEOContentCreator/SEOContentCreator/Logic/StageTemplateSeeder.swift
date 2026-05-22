import Foundation
import SwiftData

enum StageTemplateSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
        let seededStages = Set(existing.map { $0.stageRaw })

        for stage in PipelineStage.allCases where !seededStages.contains(stage.rawValue) {
            let template = makeTemplate(for: stage)
            context.insert(template)
        }
    }

    private static func makeTemplate(for stage: PipelineStage) -> StageTemplate {
        switch stage {
        case .draft:
            return StageTemplate(
                stage: .draft,
                systemPrompt: """
                Ты — медицинский редактор-копирайтер. Пиши достоверно, без искажения фактов, \
                с доказательной осторожностью. Соблюдай читабельность. Не выдумывай имена врачей, \
                процедуры и цифры — используй только переданные данные. Отвечай на русском в формате Markdown.
                """,
                userPromptTemplate: """
                Напиши черновик SEO-статьи.

                Тема: {{тема}}
                Тип статьи: {{тип}}
                Целевой объём (знаков): {{объём}}
                Направление: {{направление}}
                Данные врача: {{врач_данные}}
                Преимущества клиники: {{преимущества}}
                Приоритетные источники: {{источники_направления}}

                Сделай структуру H1/H2/H3 и связный текст. Не добавляй рекламных преувеличений.
                """
            )
        case .productBlocks:
            return StageTemplate(
                stage: .productBlocks,
                systemPrompt: """
                Ты — медицинский редактор. Встраиваешь продуктовые блоки клиники в существующий текст, \
                сохраняя структуру и стиль. Данные берёшь только из переданных. Русский, Markdown.
                """,
                userPromptTemplate: """
                Встрой выбранные продуктовые блоки в текст, не ломая его структуру.

                Текущий текст:
                {{текущий_текст}}

                Преимущества клиники: {{преимущества}}
                Данные врача: {{врач_данные}}

                Верни полный обновлённый текст статьи.
                """
            )
        case .semanticsInText:
            return StageTemplate(
                stage: .semanticsInText,
                systemPrompt: """
                Ты — SEO-редактор. Естественно встраиваешь ключевые запросы в текст без порчи русского языка \
                и без переспама. Не меняешь факты. Русский, Markdown.
                """,
                userPromptTemplate: """
                Встрой ключевые запросы в текст естественно. Учитывай частотность и обязательность. \
                Допиши/поправь H1, сгенерируй Title и Description.

                Текущий текст:
                {{текущий_текст}}

                Ключевые запросы:
                {{семантика}}

                После основного текста статьи добавь блок метаданных строго в таком формате:
                ```json
                {"h1":"...","seoTitle":"...","seoDescription":"...","embeddedQueries":["..."],"notes":"..."}
                ```
                """
            )
        }
    }
}
