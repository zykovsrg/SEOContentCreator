import Foundation

enum SemanticPromptRenderer {
    static func render(topic: Topic) -> String {
        let records = topic.semanticKeywords
            .filter { $0.userDecision == .accepted || $0.userDecision == .required }

        if records.isEmpty {
            return topic.semantics.joined(separator: "\n")
        }

        return records.map { keyword in
            if keyword.userDecision == .required {
                return "\(keyword.text) (обязательный запрос)"
            }

            return keyword.text
        }
        .joined(separator: "\n")
    }
}
