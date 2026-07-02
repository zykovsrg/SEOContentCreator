import Foundation

enum SemanticKeywordBackfill {
    static func backfill(_ topic: Topic) {
        var existingKeys = Set(topic.semanticKeywords.compactMap { canonicalKey(for: $0.text) })

        for legacyText in topic.semantics {
            let trimmedText = legacyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = canonicalKey(for: trimmedText), !existingKeys.contains(key) else {
                continue
            }

            let keyword = SemanticKeyword(
                text: trimmedText,
                agentRecommendation: .none,
                userDecision: .accepted,
                reasonCategory: .none,
                explanation: "",
                cannibalizationRisk: .none
            )
            keyword.topic = topic
            topic.semanticKeywords.append(keyword)
            existingKeys.insert(key)
        }
    }

    private static func canonicalKey(for text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }
        return trimmedText.lowercased()
    }
}
