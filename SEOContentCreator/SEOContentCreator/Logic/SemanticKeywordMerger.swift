import Foundation

enum SemanticKeywordMerger {
    static func merge(
        _ results: [SemanticAgentKeywordResult],
        into topic: Topic,
        decision: SemanticUserDecision = .pending
    ) {
        for result in results {
            let normalized = normalize(result.query)

            if let existing = topic.semanticKeywords.first(where: { normalize($0.text) == normalized }) {
                existing.frequency = result.frequency
                existing.agentRecommendation = result.recommendation
                existing.reasonCategory = result.reasonCategory
                existing.explanation = result.explanation
                existing.cannibalizationRisk = result.cannibalizationRisk
                existing.cannibalizationURL = result.cannibalizationURL
                existing.cannibalizationTitle = result.cannibalizationTitle
                // A decision the user already made is never overwritten by a re-run.
                if existing.userDecision == .pending {
                    existing.userDecision = decision
                }
                existing.updatedAt = .now
            } else {
                let keyword = SemanticKeyword(
                    text: result.query.trimmingCharacters(in: .whitespacesAndNewlines),
                    frequency: result.frequency,
                    agentRecommendation: result.recommendation,
                    userDecision: decision,
                    reasonCategory: result.reasonCategory,
                    explanation: result.explanation,
                    cannibalizationRisk: result.cannibalizationRisk,
                    cannibalizationURL: result.cannibalizationURL,
                    cannibalizationTitle: result.cannibalizationTitle
                )
                keyword.topic = topic
                topic.semanticKeywords.append(keyword)
            }
        }

        topic.updatedAt = .now
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
