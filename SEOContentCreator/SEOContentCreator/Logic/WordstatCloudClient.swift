import Foundation

/// The current, documented, self-service Wordstat API. See
/// docs/superpowers/notes/2026-07-22-wordstat-api.md for the source.
struct WordstatCloudClient {
    enum ClientError: Error, LocalizedError, Equatable {
        case missingCredentials
        case quotaExceeded
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Не заданы ключ и folderId Yandex Cloud. Добавьте их в настройках."
            case .quotaExceeded:
                return "Исчерпан лимит запросов к Wordstat (Yandex Cloud). Попробуйте позже."
            case .httpError(let code):
                return "Wordstat (Yandex Cloud) вернул ошибку \(code)."
            }
        }
    }

    /// Moscow city and Moscow region — the confirmed defaults.
    static let defaultRegions = ["213", "1"]

    var apiKey: String
    var folderID: String
    var session: URLSession = .shared

    func phrases(for seed: String) async throws -> [WordstatPhrase] {
        guard !apiKey.isEmpty, !folderID.isEmpty else { throw ClientError.missingCredentials }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Api-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "phrase": seed,
            "folderId": folderID,
            "numPhrases": 200,
            "regions": Self.defaultRegions,
            "devices": ["DEVICE_ALL"]
        ])

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? ClientError.quotaExceeded : ClientError.httpError(http.statusCode)
        }

        return try WordstatResponseParser.parse(data)
    }

    static let endpoint = URL(string: "https://searchapi.api.cloud.yandex.net/v2/wordstat/topRequests")!

    func provider() -> WordstatProvider {
        { seed in try await phrases(for: seed) }
    }
}
