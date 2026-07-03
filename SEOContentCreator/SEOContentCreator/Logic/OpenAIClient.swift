import Foundation

enum OpenAIStreamEvent: Equatable {
    case token(String)
    case finish(reason: String)
    case usage(promptTokens: Int, completionTokens: Int)
}

struct OpenAIClient {
    enum OpenAIError: Error, Equatable, LocalizedError {
        case unauthorized
        case rateLimited
        case http(Int, message: String?)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Ошибка авторизации (401): OpenAI отклонил запрос. Проверьте API-ключ в Настройках или доступ аккаунта к выбранной модели."
            case .rateLimited:
                return "Превышен лимит запросов (429). Подождите немного и попробуйте снова."
            case .http(let code, let message):
                let detail = message.map { " — \($0)" } ?? ""
                if code == 403 {
                    return "Ошибка OpenAI (HTTP 403)\(detail): нет доступа к выбранной модели или проекту. Проверьте модель изображений, API-ключ, биллинг и доступ организации в Настройках OpenAI."
                }
                return "Ошибка OpenAI (HTTP \(code))\(detail). Попробуйте позже или смените модель в разделе «Шаблоны»."
            case .badResponse:
                return "Не удалось разобрать ответ OpenAI."
            }
        }
    }

    /// Extracts OpenAI's `error.message` from a JSON error response body, if present.
    static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObj = json["error"] as? [String: Any],
              let message = errorObj["message"] as? String,
              !message.isEmpty
        else { return nil }
        return message
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
        maxTokens: Int = 8000,
        reasoningEffort: String? = nil
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
                        "stream": true,
                        "stream_options": ["include_usage": true],
                        "messages": [
                            ["role": "system", "content": system],
                            ["role": "user", "content": user]
                        ]
                    ]
                    if Self.usesMaxCompletionTokens(model: model) {
                        // GPT-5.x / o-series use max_completion_tokens and reject a
                        // custom temperature (only the default is allowed), so omit it.
                        body["max_completion_tokens"] = maxTokens
                        // reasoning_effort is supported only by these newer families.
                        if let reasoningEffort {
                            body["reasoning_effort"] = reasoningEffort
                        }
                    } else {
                        body["temperature"] = temperature
                        body["max_tokens"] = maxTokens
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        switch http.statusCode {
                        case 200...299: break
                        case 401: throw OpenAIError.unauthorized
                        case 429: throw OpenAIError.rateLimited
                        default:
                            var errorBody = Data()
                            for try await line in bytes.lines { errorBody.append(Data(line.utf8)) }
                            throw OpenAIError.http(http.statusCode, message: Self.extractErrorMessage(from: errorBody))
                        }
                    }

                    for try await line in bytes.lines {
                        switch OpenAILineParser.parse(line: line) {
                        case .token(let t): continuation.yield(.token(t))
                        case .finish(let reason): continuation.yield(.finish(reason: reason))
                        case .usage(let prompt, let completion):
                            continuation.yield(.usage(promptTokens: prompt, completionTokens: completion))
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
