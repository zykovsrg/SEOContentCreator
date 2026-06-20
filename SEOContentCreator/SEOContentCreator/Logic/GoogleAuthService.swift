import Foundation
import CryptoKit
import AppKit
import Network
import Security

@MainActor
@Observable
final class GoogleAuthService {
    enum AuthError: Error, Equatable, LocalizedError {
        case noClientCredentials
        case notSignedIn
        case cancelled
        case tokenExchangeFailed
        var errorDescription: String? {
            switch self {
            case .noClientCredentials: return "Укажите Client ID и Client Secret Google в Настройках."
            case .notSignedIn: return "Войдите в Google в Настройках."
            case .cancelled: return "Вход в Google отменён."
            case .tokenExchangeFailed: return "Не удалось получить токен Google."
            }
        }
    }

    static let scopes = ["https://www.googleapis.com/auth/documents",
                         "https://www.googleapis.com/auth/drive.file"]

    var lastErrorMessage: String?
    var isSignedIn: Bool { GoogleCredentialStore.isSignedIn }

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    // MARK: Pure helpers (tested) — nonisolated so sync tests can call them.

    nonisolated static func buildAuthURL(clientID: String, redirectURI: String, codeChallenge: String) -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        return c.url!
    }

    nonisolated static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    nonisolated static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    // MARK: Token endpoints

    func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws {
        guard let id = GoogleCredentialStore.loadClientID(),
              let secret = GoogleCredentialStore.loadClientSecret() else { throw AuthError.noClientCredentials }
        let form = [
            "code": code, "client_id": id, "client_secret": secret,
            "code_verifier": verifier, "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        let json = try await postForm(form)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else { throw AuthError.tokenExchangeFailed }
        try GoogleCredentialStore.saveTokens(GoogleTokens(
            accessToken: access, refreshToken: refresh,
            expiry: Date().addingTimeInterval(TimeInterval(expiresIn))))
    }

    func validAccessToken() async throws -> String {
        guard let tokens = GoogleCredentialStore.loadTokens() else { throw AuthError.notSignedIn }
        if !tokens.isExpired { return tokens.accessToken }
        guard let id = GoogleCredentialStore.loadClientID(),
              let secret = GoogleCredentialStore.loadClientSecret() else { throw AuthError.noClientCredentials }
        let form = [
            "client_id": id, "client_secret": secret,
            "refresh_token": tokens.refreshToken, "grant_type": "refresh_token"
        ]
        let json = try await postForm(form)
        guard let access = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else { throw AuthError.tokenExchangeFailed }
        let updated = GoogleTokens(accessToken: access, refreshToken: tokens.refreshToken,
                                   expiry: Date().addingTimeInterval(TimeInterval(expiresIn)))
        try GoogleCredentialStore.saveTokens(updated)
        return access
    }

    func signOut() { try? GoogleCredentialStore.deleteAll() }

    private func postForm(_ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.tokenExchangeFailed
        }
        return json
    }

    // MARK: Interactive sign-in (manual-tested; browser + loopback)

    func signIn() async throws {
        guard GoogleCredentialStore.loadClientID() != nil else { throw AuthError.noClientCredentials }
        let id = GoogleCredentialStore.loadClientID()!
        let verifier = Self.makeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let listener = try LoopbackListener()
        let redirect = "http://127.0.0.1:\(listener.port)"
        let authURL = Self.buildAuthURL(clientID: id, redirectURI: redirect, codeChallenge: challenge)
        NSWorkspace.shared.open(authURL)
        let code = try await listener.waitForCode()
        try await exchangeCode(code, verifier: verifier, redirectURI: redirect)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=")
        return set
    }()
}

final class LoopbackListener {
    let port: UInt16
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?

    init() throws {
        // Слушаем только loopback-интерфейс (127.0.0.1), а не все сетевые интерфейсы:
        // OAuth-перехват одноразовый, но порт не должен быть доступен извне.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let l = try NWListener(using: parameters, on: .any)
        self.listener = l
        let sem = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        l.stateUpdateHandler = { state in
            if case .ready = state, let p = l.port?.rawValue { boundPort = p; sem.signal() }
        }
        l.start(queue: .global())
        sem.wait()
        self.port = boundPort
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global())
                conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    guard let data, let request = String(data: data, encoding: .utf8) else { return }
                    let code = Self.extractCode(from: request)
                    let html = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<html><body><h3>Готово. Можно закрыть это окно и вернуться в приложение.</h3></body></html>"
                    conn.send(content: Data(html.utf8), completion: .contentProcessed { _ in conn.cancel() })
                    self?.listener.cancel()
                    if let code { self?.continuation?.resume(returning: code) }
                    else { self?.continuation?.resume(throwing: GoogleAuthService.AuthError.cancelled) }
                    self?.continuation = nil
                }
            }
        }
    }

    static func extractCode(from httpRequest: String) -> String? {
        guard let firstLine = httpRequest.components(separatedBy: "\r\n").first,
              let pathPart = firstLine.components(separatedBy: " ").dropFirst().first,
              let comps = URLComponents(string: "http://127.0.0.1\(pathPart)") else { return nil }
        return comps.queryItems?.first(where: { $0.name == "code" })?.value
    }
}
