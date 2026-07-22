import Foundation

/// The legacy OAuth-based Wordstat API. As of 2026-07-22 this endpoint fails
/// at the TLS layer (see docs/superpowers/notes/2026-07-22-wordstat-api.md) —
/// built anyway in case Yandex restores it or a different token behaves
/// differently. Only the auth mechanism (Bearer header) is documented; the
/// rest of the request/response contract — request field names, region
/// format, response shape — is unconfirmed by any live successful call. See
/// WordstatResponseParser.
struct WordstatLegacyClient {
    enum ClientError: Error, LocalizedError, Equatable {
        case missingToken
        case endpointUnavailable
        case quotaExceeded
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "Не задан токен старого API Wordstat. Добавьте его в настройках."
            case .endpointUnavailable:
                return "Старый API Wordstat недоступен (ошибка TLS-сертификата). "
                    + "Похоже, сервис отключён. Переключитесь на Yandex Cloud в настройках."
            case .quotaExceeded:
                return "Исчерпан дневной лимит запросов к старому API Wordstat. Попробуйте завтра."
            case .httpError(let code):
                return "Старый API Wordstat вернул ошибку \(code)."
            }
        }
    }

    /// Moscow city and Moscow region — the confirmed defaults.
    static let defaultRegions = [213, 1]

    var token: String
    var session: URLSession = .shared

    func phrases(for seed: String) async throws -> [WordstatPhrase] {
        guard !token.isEmpty else { throw ClientError.missingToken }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "phrase": seed,
            "regions": Self.defaultRegions
        ])

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw http.statusCode == 429 ? ClientError.quotaExceeded : ClientError.httpError(http.statusCode)
            }

            return try WordstatResponseParser.parse(data)
        } catch let error as URLError where Self.isCertificateFailure(error) {
            throw ClientError.endpointUnavailable
        }
    }

    /// Task 1 observed exactly this failure live: a certificate for
    /// wordstat.yandex.ru served on the api.wordstat.yandex.net host.
    static func isCertificateFailure(_ error: URLError) -> Bool {
        [.serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .secureConnectionFailed].contains(error.code)
    }

    static let endpoint = URL(string: "https://api.wordstat.yandex.net/v1/topRequests")!

    func provider() -> WordstatProvider {
        { seed in try await phrases(for: seed) }
    }
}
