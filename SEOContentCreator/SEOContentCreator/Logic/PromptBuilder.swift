import Foundation

struct PromptBuilder {
    func build(
        template: StageTemplate,
        topic: Topic,
        currentText: String?,
        selectedBlocks: [String] = [],
        roleContext: String = ""
    ) -> (system: String, user: String) {
        var user = template.userPromptTemplate

        let advantages = topic.attachedNodes
            .filter { $0.nodeType == .advantage }
            .map { $0.content.isEmpty ? $0.title : $0.content }
            .joined(separator: "\n")

        let sources = (topic.direction?.sources ?? []).joined(separator: "\n")
        let semantics = topic.semantics.joined(separator: "\n")
        let knowledge = topic.attachedNodes.map { node in
            node.content.isEmpty ? node.title : "\(node.title): \(node.content)"
        }.joined(separator: "\n")

        let substitutions: [String: String] = [
            "{{тема}}": topic.title,
            "{{тип}}": topic.articleType.title,
            "{{объём}}": topic.targetVolume.map(String.init) ?? "",
            "{{направление}}": topic.direction?.content ?? topic.direction?.title ?? "",
            "{{врач_данные}}": topic.doctor?.content ?? "",
            "{{преимущества}}": advantages,
            "{{источники_направления}}": sources,
            "{{семантика}}": semantics,
            "{{база_знаний}}": knowledge,
            "{{структура}}": topic.structureText,
            "{{текущий_текст}}": currentText ?? ""
        ]
        for (key, value) in substitutions {
            user = user.replacingOccurrences(of: key, with: value)
        }

        if !selectedBlocks.isEmpty {
            user += "\n\nВключить продуктовые блоки: " + selectedBlocks.joined(separator: ", ")
        }

        let system = [roleContext, template.systemPrompt]
            .compactMap { nonEmpty($0) }
            .joined(separator: "\n\n")

        return (system, user)
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
