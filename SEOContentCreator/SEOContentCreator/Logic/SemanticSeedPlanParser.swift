import Foundation

struct SemanticSeedPlan: Equatable, Sendable {
    var synonyms: [String]
    var masks: [String]
    var tails: [String]

    /// Wordstat quota is tight (each seed is one API request), so a single
    /// collection run never sends more than this many.
    static let maxSeedPhrases = 100

    /// Every phrase the Wordstat layer will pull, deduplicated, normalized,
    /// and capped at `maxSeedPhrases`. Priority under the cap: bare synonyms
    /// first (each Wordstat call already returns up to 200 related phrases,
    /// so the bare forms are the highest-yield requests), then mask
    /// combinations round-robin across synonyms, then tail combinations the
    /// same way — so a tight cap spreads coverage evenly across synonyms
    /// instead of exhausting it on the first one.
    func seedPhrases() -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func append(_ candidate: String) {
            guard result.count < Self.maxSeedPhrases else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            result.append(trimmed)
        }

        let bases = synonyms.map(SemanticRuleFilter.normalize).filter { !$0.isEmpty }

        for base in bases {
            append(base)
        }
        for mask in masks {
            let normalized = SemanticRuleFilter.normalize(mask)
            for base in bases {
                append("\(base) \(normalized)")
            }
        }
        for tail in tails {
            let normalized = SemanticRuleFilter.normalize(tail)
            for base in bases {
                append("\(base) \(normalized)")
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
