import Foundation

enum SemanticMockKeywordCollector {
    static func collect(for topic: Topic) -> [String] {
        let base = normalize(topic.title)
        guard !base.isEmpty else { return [] }

        let articleSpecific: [String]
        switch topic.articleType {
        case .disease:
            articleSpecific = [
                "\(base) лечение",
                "\(base) симптомы",
                "\(base) диагностика",
                "\(base) цена",
                "\(base) операция",
                "\(base) лучевая терапия"
            ]
        case .service:
            articleSpecific = [
                "\(base) цена",
                "\(base) стоимость",
                "\(base) запись",
                "\(base) подготовка",
                "\(base) отзывы",
                "\(base) в москве"
            ]
        case .info:
            articleSpecific = [
                "\(base) что это",
                "\(base) причины",
                "\(base) симптомы",
                "\(base) диагностика",
                "\(base) лечение",
                "\(base) профилактика"
            ]
        }

        let common = [
            "\(base) hadassah",
            "\(base) врач",
            "\(base) отзывы",
            "\(base) форум"
        ]

        var seen = Set<String>()
        return (articleSpecific + common).filter { seen.insert($0).inserted }
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }
}
