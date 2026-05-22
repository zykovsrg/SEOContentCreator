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
        TemplateVariable(token: "{{текущий_текст}}", description: "Текст текущей версии", source: "Предыдущая версия")
    ]
}
