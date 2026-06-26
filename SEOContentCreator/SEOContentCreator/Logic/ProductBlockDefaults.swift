import Foundation

struct ProductBlockDefault {
    let name: String
    let prompt: String
}

enum ProductBlockDefaults {
    static let all: [ProductBlockDefault] = [
        ProductBlockDefault(
            name: "CTA «Записаться»",
            prompt: "Добавь короткий призыв записаться на приём. Без давления и преувеличений, по делу."
        ),
        ProductBlockDefault(
            name: "Почему мы",
            prompt: "Сформируй блок «Почему мы» на основе преимуществ клиники: {{преимущества}}. Только факты из данных, ничего не выдумывай."
        ),
        ProductBlockDefault(
            name: "Блок врача",
            prompt: "Добавь блок о враче на основе данных: {{врач_данные}}. Если данных нет — пропусти блок."
        ),
        ProductBlockDefault(
            name: "Преимущества клиники",
            prompt: "Перечисли преимущества клиники: {{преимущества}}. Кратко, по пунктам, без рекламных штампов."
        )
    ]

    static func make(_ def: ProductBlockDefault, order: Int) -> ProductBlock {
        ProductBlock(name: def.name, prompt: def.prompt, order: order)
    }

    static func makeAll() -> [ProductBlock] {
        all.enumerated().map { make($0.element, order: $0.offset) }
    }
}
