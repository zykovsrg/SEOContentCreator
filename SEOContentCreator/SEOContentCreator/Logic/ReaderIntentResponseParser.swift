import Foundation

enum ReaderIntentResponseParser {
    enum ParserError: Error, Equatable, LocalizedError {
        case badResponse

        var errorDescription: String? {
            "ИИ вернул ответ в неверном формате. Попробуйте сформировать карту ещё раз."
        }
    }

    private struct Envelope: Decodable {
        var query: String
        var audienceContext: String
        var hiddenGoal: String
        var successCriterion: String
        var barriers: String
        var solutionType: String
        var solutionFormat: String
        var coverage: [String]
    }

    static func parse(_ text: String) throws -> ReaderIntentDraft {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let solutionType = ReaderIntentSolutionType(rawValue: envelope.solutionType)
        else { throw ParserError.badResponse }

        let coverage = envelope.coverage.compactMap(ReaderIntentCoverage.init(rawValue:))
        guard coverage.count == envelope.coverage.count else { throw ParserError.badResponse }

        var draft = ReaderIntentDraft()
        draft.query = clean(envelope.query)
        draft.audienceContext = clean(envelope.audienceContext)
        draft.hiddenGoal = clean(envelope.hiddenGoal)
        draft.successCriterion = clean(envelope.successCriterion)
        draft.barriers = clean(envelope.barriers)
        draft.solutionType = solutionType
        draft.solutionFormat = clean(envelope.solutionFormat)
        draft.coverage = Set(coverage)
        guard draft.canSave else { throw ParserError.badResponse }
        return draft
    }

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
