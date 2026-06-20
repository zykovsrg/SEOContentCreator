import Testing
import Foundation
@testable import SEOContentCreator

private final class MockImageURLProtocol: URLProtocol {
    nonisolated(unsafe) static var stubBody = ""
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.stubBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct ImageClientTests {
    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockImageURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func returnsDecodedImageOn200() async throws {
        let bytes = Data([10, 20, 30])
        MockImageURLProtocol.statusCode = 200
        MockImageURLProtocol.stubBody = "{\"data\":[{\"b64_json\":\"\(bytes.base64EncodedString())\"}]}"
        let client = ImageClient(session: mockSession())
        let result = try await client.generate(
            apiKey: "k", prompt: "p", model: "gpt-image-1",
            size: "1024x1024", quality: "high", references: []
        )
        #expect(result == bytes)
    }

    @Test func unauthorizedThrows() async {
        MockImageURLProtocol.statusCode = 401
        MockImageURLProtocol.stubBody = ""
        let client = ImageClient(session: mockSession())
        await #expect(throws: OpenAIClient.OpenAIError.unauthorized) {
            _ = try await client.generate(
                apiKey: "bad", prompt: "p", model: "gpt-image-1",
                size: "1024x1024", quality: "high", references: []
            )
        }
    }

    @Test func selectsEditsEndpointWhenReferencesPresent() {
        #expect(ImageClient.usesEdits(referenceCount: 0) == false)
        #expect(ImageClient.usesEdits(referenceCount: 1) == true)
    }
}
