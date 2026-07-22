import Foundation

struct SemanticSeedPlan: Equatable, Sendable {
    var synonyms: [String]
    var masks: [String]
    var tails: [String]

    /// Every phrase the Wordstat layer will pull, deduplicated and normalized.
    /// Each synonym is pulled bare, plus once per mask and once per tail.
    func seedPhrases() -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for synonym in synonyms {
            let base = SemanticRuleFilter.normalize(synonym)
            guard !base.isEmpty else { continue }

            let maskPhrases = masks.map { "\(base) \(SemanticRuleFilter.normalize($0))" }
            let tailPhrases = tails.map { "\(base) \(SemanticRuleFilter.normalize($0))" }

            for candidate in [base] + maskPhrases + tailPhrases {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
                result.append(trimmed)
            }
        }

        return result
    }
}

enum SemanticSeedPlanParser {
    enum ParserError: Error, Equatable {
        case badResponse
    }

    private struct Envelope: Decodable {
        var synonyms: [String]
        var masks: [String]
        var tails: [String]
    }

    static func parse(_ text: String) throws -> SemanticSeedPlan {
        let cleaned = stripFence(text)

        guard let data = cleaned.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ParserError.badResponse
        }

        let plan = SemanticSeedPlan(
            synonyms: clean(envelope.synonyms),
            masks: clean(envelope.masks),
            tails: clean(envelope.tails)
        )

        guard !plan.synonyms.isEmpty || !plan.masks.isEmpty || !plan.tails.isEmpty else {
            throw ParserError.badResponse
        }

        return plan
    }

    private static func clean(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Models sometimes wrap JSON in a Markdown fence despite instructions.
    private static func stripFence(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.hasPrefix("```") else { return result }

        result = result
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
