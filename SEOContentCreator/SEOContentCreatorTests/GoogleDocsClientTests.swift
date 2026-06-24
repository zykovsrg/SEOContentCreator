import Testing
import Foundation
@testable import SEOContentCreator

final class GoogleMockURLProtocol: URLProtocol {
    struct Stub { let status: Int; let body: String }
    nonisolated(unsafe) static var queue: [Stub] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let stub = Self.queue.isEmpty ? Stub(status: 200, body: "{}") : Self.queue.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct GoogleDocsClientTests {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [GoogleMockURLProtocol.self]
        return URLSession(configuration: cfg)
    }
    private func client() -> GoogleDocsClient {
        GoogleDocsClient(session: session(), tokenProvider: { "test-token" })
    }

    @Test func createDocumentReturnsID() async throws {
        GoogleMockURLProtocol.queue = [.init(status: 200, body: #"{"documentId":"doc-42"}"#)]
        GoogleMockURLProtocol.requests = []
        let id = try await client().createDocument(title: "Моя статья")
        #expect(id == "doc-42")
        let req = try #require(GoogleMockURLProtocol.requests.first)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(req.url?.absoluteString == "https://docs.googleapis.com/v1/documents")
    }

    @Test func unauthorizedMapsToError() async {
        GoogleMockURLProtocol.queue = [.init(status: 401, body: "{}")]
        let c = client()
        await #expect(throws: GoogleDocsClient.DocsError.unauthorized) {
            _ = try await c.createDocument(title: "x")
        }
    }

    @Test func findOrCreateFolderReturnsExisting() async throws {
        GoogleMockURLProtocol.queue = [
            .init(status: 200, body: #"{"files":[{"id":"folder-7","name":"SEO-статьи клиники"}]}"#)
        ]
        let id = try await client().findOrCreateFolder(name: "SEO-статьи клиники")
        #expect(id == "folder-7")
    }

    @Test func findOrCreateFolderCreatesWhenMissing() async throws {
        GoogleMockURLProtocol.queue = [
            .init(status: 200, body: #"{"files":[]}"#),
            .init(status: 200, body: #"{"id":"folder-new"}"#)
        ]
        let id = try await client().findOrCreateFolder(name: "SEO-статьи клиники")
        #expect(id == "folder-new")
    }
}
