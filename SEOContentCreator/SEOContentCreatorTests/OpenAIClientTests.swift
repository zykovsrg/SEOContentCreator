import Testing
import Foundation
@testable import SEOContentCreator

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var stubBody = ""
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override func startLoading() {
        Self.lastRequestBody = Self.bodyData(from: request)
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
        for try await event in client.streamCompletion(apiKey: "sk-x", system: "s", user: "u", model: "gpt-4.1") {
            if case .token(let t) = event { collected += t }
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

    @Test func http403MessagePointsToSettingsAndAccess() {
        let message = OpenAIClient.OpenAIError.http(403, message: nil).errorDescription ?? ""
        #expect(message.contains("доступ"))
        #expect(message.contains("Настройках"))
        #expect(!message.contains("Шаблоны"))
    }

    @Test func httpErrorDescriptionIncludesOpenAIMessage() {
        let message = OpenAIClient.OpenAIError.http(400, message: "The model `gpt-9` does not exist").errorDescription ?? ""
        #expect(message.contains("The model `gpt-9` does not exist"))
    }

    @Test func httpErrorSurfacesOpenAIMessageFromResponseBody() async {
        MockURLProtocol.statusCode = 400
        MockURLProtocol.stubBody = #"{"error":{"message":"The model `gpt-9` does not exist","type":"invalid_request_error"}}"#
        let client = OpenAIClient(session: mockSession())
        await #expect(throws: OpenAIClient.OpenAIError.http(400, message: "The model `gpt-9` does not exist")) {
            for try await _ in client.streamCompletion(apiKey: "k", system: "s", user: "u", model: "gpt-4.1") {}
        }
    }

    @Test func httpErrorWithoutParsableBodyHasNilMessage() async {
        MockURLProtocol.statusCode = 500
        MockURLProtocol.stubBody = "internal server error, not json"
        let client = OpenAIClient(session: mockSession())
        await #expect(throws: OpenAIClient.OpenAIError.http(500, message: nil)) {
            for try await _ in client.streamCompletion(apiKey: "k", system: "s", user: "u", model: "gpt-4.1") {}
        }
    }

    @Test func reportsLengthFinishReason() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = """
        data: {"choices":[{"delta":{"content":"Часть"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"length"}]}

        data: [DONE]

        """
        let client = OpenAIClient(session: mockSession())
        var text = ""
        var sawLength = false
        for try await event in client.streamCompletion(apiKey: "k", system: "s", user: "u", model: "gpt-4.1") {
            switch event {
            case .token(let t): text += t
            case .finish(let reason): if reason == "length" { sawLength = true }
            case .usage: break
            }
        }
        #expect(text == "Часть")
        #expect(sawLength)
    }

    @Test func requestsUsageInStreamOptions() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = "data: [DONE]\n\n"
        MockURLProtocol.lastRequestBody = nil
        let client = OpenAIClient(session: mockSession())
        for try await _ in client.streamCompletion(apiKey: "k", system: "s", user: "u", model: "gpt-4.1") {}
        let body = try #require(MockURLProtocol.lastRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let streamOptions = try #require(json["stream_options"] as? [String: Any])
        #expect(streamOptions["include_usage"] as? Bool == true)
    }

    @Test func yieldsUsageEventFromFinalChunk() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = """
        data: {"choices":[{"delta":{"content":"Привет"}}]}

        data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":3,"total_tokens":15}}

        data: [DONE]

        """
        let client = OpenAIClient(session: mockSession())
        var usage: (prompt: Int, completion: Int)?
        for try await event in client.streamCompletion(apiKey: "k", system: "s", user: "u", model: "gpt-4.1") {
            if case .usage(let p, let c) = event { usage = (p, c) }
        }
        #expect(usage?.prompt == 12)
        #expect(usage?.completion == 3)
    }

    @Test func newModelsUseCompletionTokensParam() {
        #expect(OpenAIClient.usesMaxCompletionTokens(model: "gpt-5.4"))
        #expect(OpenAIClient.usesMaxCompletionTokens(model: "gpt-5.3-chat-latest"))
        #expect(OpenAIClient.usesMaxCompletionTokens(model: "gpt-5.5-pro"))
        #expect(OpenAIClient.usesMaxCompletionTokens(model: "o3-mini"))
        #expect(!OpenAIClient.usesMaxCompletionTokens(model: "gpt-4.1"))
        #expect(!OpenAIClient.usesMaxCompletionTokens(model: "gpt-4o"))
        #expect(!OpenAIClient.usesMaxCompletionTokens(model: "gpt-4o-mini"))
    }

    @Test func temperatureSupportFollowsModelFamily() {
        #expect(!OpenAIClient.supportsTemperature(model: "gpt-5.5"))
        #expect(!OpenAIClient.supportsTemperature(model: "o3-mini"))
        #expect(OpenAIClient.supportsTemperature(model: "gpt-4.1"))
    }

    @Test func omitsTemperatureForNewModels() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = "data: [DONE]\n\n"
        MockURLProtocol.lastRequestBody = nil
        let client = OpenAIClient(session: mockSession())
        for try await _ in client.streamCompletion(
            apiKey: "k", system: "s", user: "u",
            model: "gpt-5.4", temperature: 0.6, maxTokens: 5000
        ) {}
        let body = try #require(MockURLProtocol.lastRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["temperature"] == nil)
        #expect(json["max_completion_tokens"] as? Int == 5000)
        #expect(json["max_tokens"] == nil)
    }

    @Test func sendsTemperatureForLegacyModels() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = "data: [DONE]\n\n"
        MockURLProtocol.lastRequestBody = nil
        let client = OpenAIClient(session: mockSession())
        for try await _ in client.streamCompletion(
            apiKey: "k", system: "s", user: "u",
            model: "gpt-4.1", temperature: 0.6, maxTokens: 5000
        ) {}
        let body = try #require(MockURLProtocol.lastRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["temperature"] as? Double == 0.6)
        #expect(json["max_tokens"] as? Int == 5000)
        #expect(json["max_completion_tokens"] == nil)
    }

    @Test func sendsReasoningEffortForNewModels() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = "data: [DONE]\n\n"
        MockURLProtocol.lastRequestBody = nil
        let client = OpenAIClient(session: mockSession())
        for try await _ in client.streamCompletion(
            apiKey: "k", system: "s", user: "u",
            model: "gpt-5.4", temperature: 0.6, maxTokens: 5000,
            reasoningEffort: "high"
        ) {}
        let body = try #require(MockURLProtocol.lastRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["reasoning_effort"] as? String == "high")
        #expect(json["max_completion_tokens"] as? Int == 5000)
    }

    @Test func omitsReasoningEffortForLegacyModels() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = "data: [DONE]\n\n"
        MockURLProtocol.lastRequestBody = nil
        let client = OpenAIClient(session: mockSession())
        for try await _ in client.streamCompletion(
            apiKey: "k", system: "s", user: "u",
            model: "gpt-4.1", temperature: 0.6, maxTokens: 5000,
            reasoningEffort: "high"
        ) {}
        let body = try #require(MockURLProtocol.lastRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["reasoning_effort"] == nil)
    }

    @Test func omitsReasoningEffortWhenNil() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = "data: [DONE]\n\n"
        MockURLProtocol.lastRequestBody = nil
        let client = OpenAIClient(session: mockSession())
        for try await _ in client.streamCompletion(
            apiKey: "k", system: "s", user: "u",
            model: "gpt-5.4", temperature: 0.6, maxTokens: 5000
        ) {}
        let body = try #require(MockURLProtocol.lastRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["reasoning_effort"] == nil)
    }
}
