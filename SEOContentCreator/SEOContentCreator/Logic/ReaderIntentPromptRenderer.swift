enum ReaderIntentPromptRenderer {
    static func render(topic: Topic) -> String {
        guard let intent = topic.readerIntent else {
            return "Карта задачи читателя не заполнена."
        }
        var lines = ["Задача читателя:", "- Запрос: \(intent.query)"]
        append("Кто и в какой ситуации", value: intent.audienceContext, to: &lines)
        append("Практическая задача", value: intent.hiddenGoal, to: &lines)
        append("Ответ полезен, если", value: intent.successCriterion, to: &lines)
        append("Барьеры и сомнения", value: intent.barriers, to: &lines)

        let typeAndFormat = [solutionTitle(intent.solutionType), clean(intent.solutionFormat)]
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
        append("Тип и формат решения", value: typeAndFormat, to: &lines)

        let coverage = ReaderIntentCoverage.allCases
            .filter(intent.coverage.contains)
            .map { coverageTitle($0) }
            .joined(separator: ", ")
        append("Необходимое покрытие", value: coverage, to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func append(_ title: String, value: String, to lines: inout [String]) {
        let value = clean(value)
        if !value.isEmpty { lines.append("- \(title): \(value)") }
    }

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func solutionTitle(_ value: ReaderIntentSolutionType) -> String {
        switch value {
        case .explanation: return "объяснение"
        case .algorithm: return "алгоритм"
        case .comparison: return "сравнение"
        case .directOffer: return "прямое предложение"
        case .mixed: return "смешанный"
        }
    }

    private static func coverageTitle(_ value: ReaderIntentCoverage) -> String {
        switch value {
        case .definition: return "определение"
        case .currentRelevance: return "актуальность сейчас"
        case .choiceComparison: return "выбор и сравнение"
        case .evidence: return "доказательства"
        case .socialProof: return "социальное подтверждение"
        case .applicationContext: return "контекст применения"
        case .risksLimitations: return "риски и ограничения"
        case .practicalSolution: return "практическое решение"
        }
    }
}
