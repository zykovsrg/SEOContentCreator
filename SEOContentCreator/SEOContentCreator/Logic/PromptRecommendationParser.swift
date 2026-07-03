import Foundation

struct ParsedPromptRecommendation: Codable {
    var problem: String
    var location: String
    var suggestion: String
}

/// Parses the `.promptAnalysis` stage's `{"recommendations":[...]}` response.
/// Mirrors `RemarksParser`'s JSON-extraction approach.
enum PromptRecommendationParser {
    private struct Wrapper: Codable { let recommendations: [ParsedPromptRecommendation] }

    static func parse(rawText: String) -> [ParsedPromptRecommendation] {
        guard let json = extractJSON(from: rawText),
              let data = json.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data)
        else { return [] }
        return wrapper.recommendations
    }

    private static func extractJSON(from text: String) -> String? {
        if let fence = text.range(of: "```json"),
           let end = text.range(of: "```", range: fence.upperBound..<text.endIndex) {
            return String(text[fence.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last {
            return String(text[first...last])
        }
        return nil
    }
}
