import Testing
import Foundation
@testable import SEOContentCreator

private final class AuthMockURLProtocol: URLProtocol {
    struct Stub { let status: Int; let body: String }
    nonisolated(unsafe) static var queue: [Stub] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let stub = Self.queue.isEmpty ? Stub(status: 200, body: "{}") : Self.queue.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension GoogleKeychainTests {
    @Suite(.serialized)
    struct Auth {
        private func session() -> URLSession {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.protocolClasses = [AuthMockURLProtocol.self]
            return URLSession(configuration: cfg)
        }

        @Test func authURLContainsScopesAndPKCE() {
            let url = GoogleAuthService.buildAuthURL(
                clientID: "cid", redirectURI: "http://127.0.0.1:5555", codeChallenge: "chal"
            )
            let s = url.absoluteString
            #expect(s.contains("client_id=cid"))
            #expect(s.contains("code_challenge=chal"))
            #expect(s.contains("code_challenge_method=S256"))
            #expect(s.contains("access_type=offline"))
            #expect(s.contains("documents"))
            #expect(s.contains("drive.file"))
        }

        @Test func exchangeCodeStoresTokens() async throws {
            try? GoogleCredentialStore.deleteAll()
            try GoogleCredentialStore.saveClient(id: "cid", secret: "sec")
            AuthMockURLProtocol.queue = [.init(status: 200,
                body: #"{"access_token":"at1","refresh_token":"rt1","expires_in":3600}"#)]
            let auth = await GoogleAuthService(session: session())
            try await auth.exchangeCode("the-code", verifier: "ver", redirectURI: "http://127.0.0.1:5555")
            let tokens = try #require(GoogleCredentialStore.loadTokens())
            #expect(tokens.accessToken == "at1")
            #expect(tokens.refreshToken == "rt1")
        }

        @Test func validAccessTokenRefreshesWhenExpired() async throws {
            try? GoogleCredentialStore.deleteAll()
            try GoogleCredentialStore.saveClient(id: "cid", secret: "sec")
            try GoogleCredentialStore.saveTokens(GoogleTokens(
                accessToken: "old", refreshToken: "rt", expiry: Date(timeIntervalSince1970: 0)))
            AuthMockURLProtocol.queue = [.init(status: 200,
                body: #"{"access_token":"fresh","expires_in":3600}"#)]
            let auth = await GoogleAuthService(session: session())
            let token = try await auth.validAccessToken()
            #expect(token == "fresh")
        }

        @Test func validAccessTokenThrowsWhenNotSignedIn() async throws {
            try? GoogleCredentialStore.deleteAll()
            let auth = await GoogleAuthService(session: session())
            await #expect(throws: GoogleAuthService.AuthError.notSignedIn) {
                _ = try await auth.validAccessToken()
            }
        }

        @Test func extractsCodeFromHTTPRequest() {
            let req = "GET /?code=ABC123&scope=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            #expect(LoopbackListener.extractCode(from: req) == "ABC123")
        }
    }
}
