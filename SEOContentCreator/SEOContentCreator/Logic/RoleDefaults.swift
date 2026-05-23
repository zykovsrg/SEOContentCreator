import Foundation

struct ContextBlockDefault {
    let key: String
    let title: String
    let text: String
}

enum ContextBlockDefaults {
    static let canonicalOrder = ["editorialPolicy", "sources", "seoGuidelines"]

    static let all: [ContextBlockDefault] = [
        ContextBlockDefault(
            key: "editorialPolicy",
            title: "Редполитика",
            text: """
            Редполитика:
            - Пиши достоверно, спокойно и понятно для пациента.
            - Соблюдай доказательную осторожность: не обещай результат и не делай категоричных медицинских выводов без данных.
            - Не выдумывай имена врачей, процедуры, цены, сроки, проценты и другие проверяемые данные.
            - Не добавляй рекламных преувеличений и медицинских гарантий.
            """
        ),
        ContextBlockDefault(
            key: "sources",
            title: "Источники",
            text: """
            Принципы работы с источниками:
            - Опираться на переданные данные клиники и приоритетные источники направления.
            - Если данных не хватает, обозначай это аккуратно, не заполняй пробелы фантазией.
            - Для медицинских утверждений выбирай доказательную, проверяемую формулировку.
            """
        ),
        ContextBlockDefault(
            key: "seoGuidelines",
            title: "SEO-рекомендации",
            text: """
            SEO-рекомендации:
            - Проверяй структуру H1/H2/H3, Title и Description.
            - Ключевые запросы должны быть встроены естественно, без переспама и порчи русского языка.
            - Следи за объёмом, полнотой ответа на интент и отсутствием рекламности.
            """
        )
    ]

    static func defaultForKey(_ key: String) -> ContextBlockDefault? {
        all.first { $0.key == key }
    }
}

struct RoleDefault {
    let key: String
    let name: String
    let mandate: String
    let blockKeys: [String]
}

enum RoleDefaults {
    static let all: [RoleDefault] = [
        RoleDefault(
            key: "author",
            name: "ИИ-автор",
            mandate: "Ты — медицинский редактор-копирайтер. Пиши убедительно, достоверно и понятно для пациента. Отвечай на русском языке в формате Markdown.",
            blockKeys: ["editorialPolicy", "sources"]
        ),
        RoleDefault(
            key: "seo",
            name: "ИИ-SEO",
            mandate: "Ты — придирчивый SEO-редактор медицинских статей. Не переписывай текст целиком: находи проблемы, сомневайся, сверяй и предлагай точечные правки. Отвечай на русском языке в формате Markdown.",
            blockKeys: ["seoGuidelines"]
        ),
        RoleDefault(
            key: "factChecker",
            name: "ИИ-фактчекер",
            mandate: "Ты — придирчивый медицинский фактчекер. Сверяй факты с переданными данными и источниками, не переписывай текст целиком. Отвечай на русском языке в формате Markdown.",
            blockKeys: ["sources"]
        ),
        RoleDefault(
            key: "editor",
            name: "ИИ-редактор",
            mandate: "Ты — придирчивый литературный редактор-корректор медицинских текстов. Не переписывай весь текст: находи конкретные проблемы и предлагай точечные правки. Отвечай на русском языке в формате Markdown.",
            blockKeys: ["editorialPolicy"]
        )
    ]

    static func defaultForKey(_ key: String) -> RoleDefault? {
        all.first { $0.key == key }
    }
}

enum RoleContextAssembler {
    static func assemble(role: AIRole, blocks: [ContextBlock]) -> String {
        let selectedKeys = Set(role.blockKeys)
        var blocksByKey: [String: ContextBlock] = [:]
        for block in blocks where blocksByKey[block.key] == nil {
            blocksByKey[block.key] = block
        }
        var parts: [String] = []

        if let mandate = nonEmpty(role.mandate) {
            parts.append(mandate)
        }

        for key in ContextBlockDefaults.canonicalOrder where selectedKeys.contains(key) {
            guard let block = blocksByKey[key], let text = nonEmpty(block.text) else { continue }
            parts.append(text)
        }

        return parts.joined(separator: "\n\n")
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
