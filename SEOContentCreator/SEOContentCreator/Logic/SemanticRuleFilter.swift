import Foundation

struct SemanticDroppedPhrase: Equatable, Sendable {
    var phrase: WordstatPhrase
    var reason: String
}

struct SemanticRuleFilterResult: Equatable, Sendable {
    var survivors: [WordstatPhrase]
    var dropped: [SemanticDroppedPhrase]
}

/// Layer 1 of the funnel: cheap, offline, deterministic.
/// Order is deliberate — the limit is applied last so junk does not consume slots.
enum SemanticRuleFilter {
    static func apply(
        _ phrases: [WordstatPhrase],
        stopWords: [String],
        threshold: Int,
        limit: Int
    ) -> SemanticRuleFilterResult {
        var dropped: [SemanticDroppedPhrase] = []
        var byKey: [String: WordstatPhrase] = [:]
        var order: [String] = []

        let normalizedStopWords = stopWords
            .map(normalize)
            .filter { !$0.isEmpty }

        for phrase in phrases {
            let key = normalize(phrase.text)
            guard !key.isEmpty else { continue }

            if let matched = normalizedStopWords.first(where: { containsWord($0, in: key) }) {
                dropped.append(SemanticDroppedPhrase(phrase: phrase, reason: "минус-слово «\(matched)»"))
                continue
            }

            if phrase.frequency < threshold {
                dropped.append(SemanticDroppedPhrase(
                    phrase: phrase,
                    reason: "частотность \(phrase.frequency) ниже порога \(threshold)"
                ))
                continue
            }

            if let existing = byKey[key] {
                byKey[key] = WordstatPhrase(text: existing.text, frequency: max(existing.frequency, phrase.frequency))
            } else {
                byKey[key] = phrase
                order.append(key)
            }
        }

        let deduplicated = order.compactMap { byKey[$0] }
        let sorted = deduplicated.sorted { $0.frequency > $1.frequency }

        guard sorted.count > limit else {
            return SemanticRuleFilterResult(survivors: sorted, dropped: dropped)
        }

        for phrase in sorted[limit...] {
            dropped.append(SemanticDroppedPhrase(phrase: phrase, reason: "не вошёл в топ-\(limit) по частотности"))
        }

        return SemanticRuleFilterResult(survivors: Array(sorted[..<limit]), dropped: dropped)
    }

    /// Lowercases, unifies ё/е, and collapses whitespace so duplicates match.
    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Whole-word match, so "тест" does not remove "тестостерон".
    private static func containsWord(_ word: String, in normalizedText: String) -> Bool {
        normalizedText.split(separator: " ").contains { $0 == word }
    }
}
