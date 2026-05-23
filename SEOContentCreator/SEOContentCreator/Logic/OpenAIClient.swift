import Foundation

enum OpenAIStreamEvent: Equatable {
    case token(String)
    case finish(reason: String)
}

struct OpenAIClient {
    enum OpenAIError: Error, Equatable {
        case unauthorized
        case rateLimited
        case http(Int)
        case badResponse
    }

    let session: URLSession
    let endpoint: URL

    init(session: URLSession = .shared,
         endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!) {
        self.session = session
        self.endpoint = endpoint
    }

    /// Newer model families (GPT-5.x, o-series) require `max_completion_tokens`
    /// on the Chat Completions API; legacy models still use `max_tokens`.
    static func usesMaxCompletionTokens(model: String) -> Bool {
        let m = model.lowercased()
        return m.hasPrefix("gpt-5") || m.hasPrefix("o1") || m.hasPrefix("o3")
            || m.hasPrefix("o4") || m == "chat-latest"
    }

    func streamCompletion(
        apiKey: String,
        system: String,
        user: String,
        model: String,
        temperature: Double = 0.6,
        maxTokens: Int = 8000
    ) -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    var body: [String: Any] = [
                        "model": model,
                        "temperature": temperature,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": system],
                            ["role": "user", "content": user]
                        ]
                    ]
                    let tokenParam = Self.usesMaxCompletionTokens(model: model)
                        ? "max_completion_tokens" : "max_tokens"
                    body[tokenParam] = maxTokens
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        switch http.statusCode {
                        case 200...299: break
                        case 401: throw OpenAIError.unauthorized
                        case 429: throw OpenAIError.rateLimited
                        default: throw OpenAIError.http(http.statusCode)
                        }
                    }

                    for try await line in bytes.lines {
                        switch OpenAILineParser.parse(line: line) {
                        case .token(let t): continuation.yield(.token(t))
                        case .finish(let reason): continuation.yield(.finish(reason: reason))
                        case .done: continuation.finish(); return
                        case .ignore: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
