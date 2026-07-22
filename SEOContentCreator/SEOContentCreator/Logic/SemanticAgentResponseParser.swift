import Foundation

struct SemanticAgentKeywordResult: Equatable {
    var query: String
    var frequency: Int?
    var recommendation: SemanticAgentRecommendation
    var reasonCategory: SemanticReasonCategory
    var explanation: String
    var cannibalizationRisk: SemanticCannibalizationRisk
    var cannibalizationURL: String?
    var cannibalizationTitle: String?
}

struct SemanticAgentAnalysis: Equatable {
    var keywords: [SemanticAgentKeywordResult]
    var longTail: [String]
}

enum SemanticAgentResponseParser {
    enum ParserError: Error, Equatable {
        case badResponse
    }

    private struct Envelope: Decodable {
        var keywords: [Item]
        var longTail: [String]?
    }

    private struct Item: Decodable {
        var query: String
        var frequency: Int?
        var recommendation: String
        var reasonCategory: String
        var explanation: String
        // Optional: the relevance-only analyzer no longer asks the model to assess cannibalization;
        // a later cannibalization-checking service will populate this from real page data.
        var cannibalizationRisk: String?
        var cannibalizationURL: String?
        var cannibalizationTitle: String?
    }

    static func parse(_ text: String) throws -> SemanticAgentAnalysis {
        guard let data = text.data(using: .utf8) else {
            throw ParserError.badResponse
        }

        let decoder = JSONDecoder()

        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw ParserError.badResponse
        }

        var results: [SemanticAgentKeywordResult] = []

        for item in envelope.keywords {
            let query = item.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw ParserError.badResponse
            }

            guard let recommendation = SemanticAgentRecommendation(rawValue: item.recommendation),
                  let reasonCategory = SemanticReasonCategory(rawValue: item.reasonCategory),
                  let cannibalizationRisk = SemanticCannibalizationRisk(rawValue: item.cannibalizationRisk ?? "none") else {
                throw ParserError.badResponse
            }

            results.append(SemanticAgentKeywordResult(
                query: query,
                frequency: item.frequency,
                recommendation: recommendation,
                reasonCategory: reasonCategory,
                explanation: item.explanation,
                cannibalizationRisk: cannibalizationRisk,
                cannibalizationURL: item.cannibalizationURL,
                cannibalizationTitle: item.cannibalizationTitle
            ))
        }

        let longTail = (envelope.longTail ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return SemanticAgentAnalysis(keywords: results, longTail: longTail)
    }
}
