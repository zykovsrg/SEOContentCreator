import Foundation

struct TemplateVariable: Identifiable {
    var id: String { token }
    let token: String
    let description: String
    let source: String
}

enum TemplateVariables {
    /// Read-only registry mirroring PromptBuilder substitutions (spec §2.5).
    static let all: [TemplateVariable] = [
        TemplateVariable(token: "{{тема}}", description: "Название темы", source: "Бриф"),
        TemplateVariable(token: "{{тип}}", description: "Тип статьи", source: "Бриф"),
        TemplateVariable(token: "{{объём}}", description: "Целевой объём, знаков", source: "Бриф"),
        TemplateVariable(token: "{{направление}}", description: "Направление (описание/название)", source: "Бриф / База знаний"),
        TemplateVariable(token: "{{врач_данные}}", description: "Данные выбранного врача", source: "База знаний"),
        TemplateVariable(token: "{{преимущества}}", description: "Преимущества клиники (прикреплённые узлы)", source: "База знаний"),
        TemplateVariable(token: "{{источники_направления}}", description: "Приоритетные источники направления", source: "База знаний"),
        TemplateVariable(token: "{{семантика}}", description: "Список ключевых запросов", source: "Семантика"),
        TemplateVariable(token: "{{база_знаний}}", description: "Все прикреплённые узлы (для фактчекинга)", source: "База знаний"),
        TemplateVariable(token: "{{структура}}", description: "Утверждённый план статьи", source: "Этап «Структура»"),
        TemplateVariable(token: "{{выделенный_фрагмент}}", description: "Фрагмент текста для иллюстрации", source: "Окно генерации иллюстрации"),
        TemplateVariable(token: "{{текущий_текст}}", description: "Текст текущей версии", source: "Предыдущая версия"),
        TemplateVariable(token: "{{текущий_h1}}", description: "H1 текущей версии (если задан этапом «Семантика-в-текст»)", source: "Предыдущая версия"),
        TemplateVariable(token: "{{текущий_title}}", description: "SEO Title текущей версии", source: "Предыдущая версия"),
        TemplateVariable(token: "{{текущий_description}}", description: "SEO Description текущей версии", source: "Предыдущая версия"),
        TemplateVariable(token: "{{запрещённые_формулировки}}", description: "Таблица запрещённых формулировок", source: "Шаблоны → Запрещённые формулировки")
    ]
}
