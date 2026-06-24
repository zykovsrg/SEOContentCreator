import Foundation

struct SkillPresetDefault {
    let name: String
    let prompt: String
    let roleKey: String
}

enum SkillPresetDefaults {
    static let all: [SkillPresetDefault] = [
        SkillPresetDefault(
            name: "Переписать в инфостиле",
            prompt: "Перепиши фрагмент в инфостиле: коротко, ясно, без воды и канцелярита. Сохрани смысл и все факты, ничего не выдумывай.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            name: "Упростить",
            prompt: "Упрости фрагмент: сделай предложения короче и понятнее для пациента. Сохрани смысл и все факты.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            name: "Уточнить",
            prompt: "Сделай фрагмент точнее и конкретнее, убери размытые формулировки. Не добавляй новых фактов, которых нет в исходном тексте.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            name: "Убрать канцелярит",
            prompt: "Убери из фрагмента канцелярит и штампы, сделай язык живым и точным. Сохрани смысл и все факты.",
            roleKey: "editor"
        )
    ]

    static func make(_ def: SkillPresetDefault, order: Int) -> SkillPreset {
        SkillPreset(name: def.name, prompt: def.prompt, roleKey: def.roleKey, order: order)
    }

    static func makeAll() -> [SkillPreset] {
        all.enumerated().map { make($0.element, order: $0.offset) }
    }
}
