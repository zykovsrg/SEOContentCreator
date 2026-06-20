import Foundation

struct ImagePromptBuilder {
    func subject(template: ImagePromptTemplate, topic: Topic, fragment: String) -> String {
        var text = template.userPromptTemplate
        let substitutions: [String: String] = [
            "{{тема}}": topic.title,
            "{{структура}}": topic.structureText,
            "{{выделенный_фрагмент}}": fragment
        ]
        for (key, value) in substitutions {
            text = text.replacingOccurrences(of: key, with: value)
        }
        return text
    }

    func compose(subject: String, preset: ImageStylePreset?) -> String {
        let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = (preset?.styleText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return style.isEmpty ? s : s + "\n\n" + style
    }
}
