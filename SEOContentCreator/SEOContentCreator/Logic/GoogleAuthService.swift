import Foundation
import CryptoKit
import AppKit
import Security

@MainActor
@Observable
final class GoogleAuthService {
    enum AuthError: Error, Equatable, LocalizedError {
        case noClientCredentials
        case notSignedIn
        case cancelled
        case tokenExchangeFailed
        case listenerFailed(String)
        case browserOpenFailed(String)
        var errorDescription: String? {
            switch self {
            case .noClientCredentials: return "Укажите Client ID и Client Secret Google в Настройках."
            case .notSignedIn: return "Войдите в Google в Настройках."
            case .cancelled: return "Вход в Google отменён."
            case .tokenExchangeFailed: return "Не удалось получить токен Google."
            case .listenerFailed(let reason): return "Не удалось открыть локальный порт для входа: \(reason)"
            case .browserOpenFailed(let reason): return "Не удалось открыть браузер для входа: \(reason)"
            }
        }
    }

    nonisolated static let scopes = ["https://www.googleapis.com/auth/documents",
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
        guard let id = GoogleCredentialStore.loadClientID() else { throw AuthError.noClientCredentials }
        let verifier = Self.makeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let listener = try LoopbackListener()
        let redirect = "http://127.0.0.1:\(listener.port)"
        let authURL = Self.buildAuthURL(clientID: id, redirectURI: redirect, codeChallenge: challenge)
        try await openInBrowser(authURL)
        let code = try await listener.waitForCode()
        try await exchangeCode(code, verifier: verifier, redirectURI: redirect)
    }

    /// Открывает системный браузер на URL входа Google.
    ///
    /// Используем современный async-вариант `open(_:configuration:)`, а не
    /// устаревший `open(_ url:) -> Bool`: на свежих macOS устаревший вызов может
    /// молча ничего не делать, из-за чего вход «зависал» без единого сообщения.
    /// Здесь любая неудача превращается в понятную ошибку.
    private func openInBrowser(_ url: URL) async throws {
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw AuthError.browserOpenFailed(error.localizedDescription)
        }
    }
}

extension Data {
    nonisolated func base64URLEncodedString() -> String {
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

/// Локальный одноразовый слушатель для перехвата OAuth-redirect от Google.
///
/// Использует обычный POSIX-сокет, а не `NWListener`: на macOS 26.x
/// `NWListener` падает с EINVAL (POSIX 22) на любой конфигурации, тогда как
/// BSD-сокет работает штатно. Привязка строго к 127.0.0.1 гарантирует, что
/// порт доступен только с этого компьютера (loopback), а не из сети.
final class LoopbackListener {
    private(set) var port: UInt16 = 0
    private let fd: Int32
    private let queue = DispatchQueue(label: "google.loopback.listener")

    init() throws {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { throw GoogleAuthService.AuthError.listenerFailed("socket: \(Self.errnoText())") }

        var yes: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0                              // эфемерный порт
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")  // только loopback

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(s); throw GoogleAuthService.AuthError.listenerFailed("bind: \(Self.errnoText())")
        }
        guard listen(s, 1) == 0 else {
            close(s); throw GoogleAuthService.AuthError.listenerFailed("listen: \(Self.errnoText())")
        }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) }
        }
        self.fd = s
        self.port = UInt16(bigEndian: bound.sin_port)
    }

    /// Ждёт одно входящее соединение (redirect из браузера), читает запрос,
    /// извлекает параметр `code`, отвечает короткой страницей и закрывает сокет.
    func waitForCode() async throws -> String {
        let fd = self.fd
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    cont.resume(throwing: GoogleAuthService.AuthError.listenerFailed("accept: \(Self.errnoText())"))
                    return
                }
                defer { close(client) }

                var buffer = [UInt8](repeating: 0, count: 8192)
                let n = recv(client, &buffer, buffer.count, 0)
                let request = n > 0 ? String(decoding: buffer[0..<n], as: UTF8.self) : ""
                let code = Self.extractCode(from: request)

                let html = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><body><h3>Готово. Можно закрыть это окно и вернуться в приложение.</h3></body></html>"
                let responseBytes = Array(html.utf8)
                _ = responseBytes.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }

                if let code { cont.resume(returning: code) }
                else { cont.resume(throwing: GoogleAuthService.AuthError.cancelled) }
            }
        }
    }

    deinit { close(fd) }

    private static func errnoText() -> String {
        "errno \(errno) (\(String(cString: strerror(errno))))"
    }

    static func extractCode(from httpRequest: String) -> String? {
        guard let firstLine = httpRequest.components(separatedBy: "\r\n").first,
              let pathPart = firstLine.components(separatedBy: " ").dropFirst().first,
              let comps = URLComponents(string: "http://127.0.0.1\(pathPart)") else { return nil }
        return comps.queryItems?.first(where: { $0.name == "code" })?.value
    }
}
