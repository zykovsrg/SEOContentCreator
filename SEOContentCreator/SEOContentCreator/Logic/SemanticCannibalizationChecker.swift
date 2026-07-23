import Foundation

struct SemanticCannibalizationResult: Equatable {
    var query: String
    var risk: SemanticCannibalizationRisk
    var url: String?
    var title: String?
}

enum SemanticCannibalizationParser {
    enum ParserError: Error, Equatable {
        case badResponse
    }

    private struct Envelope: Decodable {
        var results: [Item]
    }

    private struct Item: Decodable {
        var query: String
        var risk: String
        var url: String?
        var title: String?
    }

    static func parse(_ text: String) throws -> [SemanticCannibalizationResult] {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ParserError.badResponse
        }

        return try envelope.results.map { item in
            guard let risk = SemanticCannibalizationRisk(rawValue: item.risk) else {
                throw ParserError.badResponse
            }
            return SemanticCannibalizationResult(query: item.query, risk: risk, url: item.url, title: item.title)
        }
    }
}

/// Layer 3 of the funnel. Split from the relevance analyzer so neither prompt
/// grows large enough to degrade the other.
@MainActor
struct SemanticCannibalizationChecker {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = StageExecutor.KeyProvider

    let streamProvider: StreamProvider
    let keyProvider: KeyProvider
    let model: String

    static func live(model: String) -> SemanticCannibalizationChecker {
        SemanticCannibalizationChecker(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens, reasoningEffort in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey,
                    system: system,
                    user: user,
                    model: model,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    reasoningEffort: reasoningEffort
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() },
            model: model
        )
    }

    func check(
        keywords: [SemanticAgentKeywordResult],
        pages: [PublishedSitePage]
    ) async throws -> [SemanticAgentKeywordResult] {
        guard !keywords.isEmpty else { return keywords }

        let key = try keyProvider()
        var collected = ""

        for try await event in streamProvider(
            key,
            Self.systemPrompt,
            Self.userPrompt(keywords: keywords, pages: pages),
            model,
            0.2,
            3000,
            nil
        ) {
            if case .token(let token) = event {
                collected += token
            }
        }

        let results = try SemanticCannibalizationParser.parse(collected)
        let byQuery = Dictionary(results.map { ($0.query, $0) }, uniquingKeysWith: { first, _ in first })

        return keywords.map { keyword in
            guard let match = byQuery[keyword.query] else { return keyword }

            var updated = keyword
            updated.cannibalizationRisk = match.risk
            updated.cannibalizationURL = match.url
            updated.cannibalizationTitle = match.title
            // Only a serious clash rewrites the reason the editor sees.
            if match.risk == .high || match.risk == .medium {
                updated.reasonCategory = .cannibalization
            }
            return updated
        }
    }

    static let systemPrompt = """
    Ты SEO-аналитик медицинского сайта. Верни только JSON без Markdown.
    Самостоятельно, без стороннего сервиса, оцени, конкурирует ли каждый запрос
    с уже опубликованными страницами сайта.
    Если конкуренции нет, не включай запрос в ответ.
    """

    static func userPrompt(keywords: [SemanticAgentKeywordResult], pages: [PublishedSitePage]) -> String {
        """
        Запросы:
        \(keywords.map { "- \($0.query)" }.joined(separator: "\n"))

        Опубликованные страницы сайта:
        \(pages.map(\.summaryForAgent).joined(separator: "\n\n---\n\n"))

        Верни JSON:
        {"results":[{"query":"...","risk":"low|medium|high","url":"адрес конкурирующей страницы или null","title":"заголовок или null"}]}
        """
    }
}
