import Foundation

/// Shape confirmed for the Cloud API's `/topRequests` response
/// (docs/superpowers/notes/2026-07-22-wordstat-api.md). Reused as a
/// best-effort guess for the legacy API too, since its response shape was
/// never actually observed.
enum WordstatResponseParser {
    enum ParserError: Error, Equatable {
        case badResponse
    }

    private struct Response: Decodable {
        struct Phrase: Decodable {
            var phrase: String
            var count: String
        }
        var results: [Phrase]
    }

    static func parse(_ data: Data) throws -> [WordstatPhrase] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ParserError.badResponse
        }

        return response.results.compactMap { item in
            let text = item.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let count = Int(item.count) else { return nil }
            return WordstatPhrase(text: text, frequency: max(0, count))
        }
    }
}
