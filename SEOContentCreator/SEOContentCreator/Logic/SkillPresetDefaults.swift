import Foundation

struct SkillPresetDefault {
    /// Stable identifier, independent of the user-editable name.
    let key: String
    let name: String
    let prompt: String
    let roleKey: String
}

enum SkillPresetDefaults {
    static let all: [SkillPresetDefault] = [
        SkillPresetDefault(
            key: "infostyle",
            name: "Переписать в инфостиле",
            prompt: "Перепиши фрагмент в инфостиле: коротко, ясно, без воды и канцелярита. Сохрани смысл и все факты, ничего не выдумывай.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            key: "simplify",
            name: "Упростить",
            prompt: "Упрости фрагмент: сделай предложения короче и понятнее для пациента. Сохрани смысл и все факты.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            key: "clarify",
            name: "Уточнить",
            prompt: "Сделай фрагмент точнее и конкретнее, убери размытые формулировки. Не добавляй новых фактов, которых нет в исходном тексте.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            key: "decancel",
            name: "Убрать канцелярит",
            prompt: "Убери из фрагмента канцелярит и штампы, сделай язык живым и точным. Сохрани смысл и все факты.",
            roleKey: "editor"
        )
    ]

    static func make(_ def: SkillPresetDefault, order: Int) -> SkillPreset {
        SkillPreset(name: def.name, prompt: def.prompt, roleKey: def.roleKey, order: order, defaultKey: def.key)
    }

    static func makeAll() -> [SkillPreset] {
        all.enumerated().map { make($0.element, order: $0.offset) }
    }
}
