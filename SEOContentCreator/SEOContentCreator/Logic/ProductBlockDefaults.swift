import Foundation

struct ProductBlockDefault {
    /// Stable identifier, independent of the user-editable name.
    let key: String
    let name: String
    let prompt: String
}

enum ProductBlockDefaults {
    static let all: [ProductBlockDefault] = [
        ProductBlockDefault(
            key: "cta_signup",
            name: "CTA «Записаться»",
            prompt: "Добавь короткий призыв записаться на приём. Без давления и преувеличений, по делу."
        ),
        ProductBlockDefault(
            key: "why_us",
            name: "Почему мы",
            prompt: "Сформируй блок «Почему мы» на основе преимуществ клиники: {{преимущества}}. Только факты из данных, ничего не выдумывай."
        ),
        ProductBlockDefault(
            key: "doctor",
            name: "Блок врача",
            prompt: "Добавь блок о враче на основе данных: {{врач_данные}}. Если данных нет — пропусти блок."
        ),
        ProductBlockDefault(
            key: "clinic_advantages",
            name: "Преимущества клиники",
            prompt: "Перечисли преимущества клиники: {{преимущества}}. Кратко, по пунктам, без рекламных штампов."
        )
    ]

    static func make(_ def: ProductBlockDefault, order: Int) -> ProductBlock {
        ProductBlock(name: def.name, prompt: def.prompt, order: order, defaultKey: def.key)
    }

    static func makeAll() -> [ProductBlock] {
        all.enumerated().map { make($0.element, order: $0.offset) }
    }
}
