enum ReaderIntentPromptBuilder {
    static let systemPrompt = """
    Ты анализируешь поисковый интент читателя медицинской страницы. Верни только JSON без Markdown.
    Не выдумывай медицинские факты. Неподтверждённые предположения об аудитории, страхах и мотивах формулируй как гипотезы. Не используй запугивание. Выбирай только действительно нужные категории покрытия, а не все восемь по умолчанию.
    Формат ответа:
    Обязательные ключи объекта: query, audienceContext, hiddenGoal, successCriterion, barriers, solutionType, solutionFormat, coverage. Первые семь значений — строки. solutionType — одно из explanation, algorithm, comparison, directOffer, mixed. coverage — массив только из definition, currentRelevance, choiceComparison, evidence, socialProof, applicationContext, risksLimitations, practicalSolution.
    """

    static func userPrompt(topic: Topic) -> String {
        let semantics = ReaderIntent.acceptedSemanticSnapshot(for: topic)
        let semanticText = semantics.isEmpty
            ? "Принятых или обязательных запросов нет; вывод будет менее уверенным."
            : semantics.map { "- \($0)" }.joined(separator: "\n")

        var seen = Set<String>()
        let nodes = ([topic.direction, topic.doctor] + topic.attachedNodes.map(Optional.some))
            .compactMap { $0 }
            .filter { node in
                let key = "\(node.title)\u{0}\(node.content)"
                return seen.insert(key).inserted
            }
        let knowledge = nodes.isEmpty
            ? "(нет прикреплённых данных)"
            : nodes.map { node in
                let body = node.content.isEmpty ? node.title : "\(node.title): \(node.content)"
                let sources = node.sources.isEmpty ? "" : "\nИсточники: \(node.sources.joined(separator: ", "))"
                return "[\(node.nodeType.title)] \(body)\(sources)"
            }.joined(separator: "\n\n")

        return """
        Проанализируй данные темы и заполни одну карту задачи читателя в указанном JSON-формате.

        Тема: \(topic.title)
        Тип статьи: \(topic.articleType.title)

        Принятые и обязательные поисковые запросы:
        \(semanticText)

        Данные этой темы из базы знаний:
        \(knowledge)
        """
    }
}
