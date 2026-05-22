import Testing
import Foundation
@testable import SEOContentCreator

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var stubBody = ""
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.stubBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct OpenAIClientTests {
    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func streamsTokensFromSSE() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = """
        data: {"choices":[{"delta":{"content":"Привет"}}]}

        data: {"choices":[{"delta":{"content":", мир"}}]}

        data: [DONE]

        """
        let client = OpenAIClient(session: mockSession())
        var collected = ""
        for try await token in client.streamCompletion(apiKey: "sk-x", system: "s", user: "u", model: "gpt-4.1") {
            collected += token
        }
        #expect(collected == "Привет, мир")
    }

    @Test func unauthorizedThrows() async {
        MockURLProtocol.statusCode = 401
        MockURLProtocol.stubBody = ""
        let client = OpenAIClient(session: mockSession())
        await #expect(throws: OpenAIClient.OpenAIError.unauthorized) {
            for try await _ in client.streamCompletion(apiKey: "bad", system: "s", user: "u", model: "gpt-4.1") {}
        }
    }
}
