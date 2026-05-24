import Testing
import Foundation
@testable import SEOContentCreator

@Suite(.serialized)
struct ImageClientTests {
    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func returnsDecodedImageOn200() async throws {
        let bytes = Data([10, 20, 30])
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = "{\"data\":[{\"b64_json\":\"\(bytes.base64EncodedString())\"}]}"
        let client = ImageClient(session: mockSession())
        let result = try await client.generate(
            apiKey: "k", prompt: "p", model: "gpt-image-1",
            size: "1024x1024", quality: "high", references: []
        )
        #expect(result == bytes)
    }

    @Test func unauthorizedThrows() async {
        MockURLProtocol.statusCode = 401
        MockURLProtocol.stubBody = ""
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
