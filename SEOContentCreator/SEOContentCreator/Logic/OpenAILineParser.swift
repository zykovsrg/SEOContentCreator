import Foundation

enum OpenAILineResult: Equatable {
    case token(String)
    case finish(reason: String)
    case usage(promptTokens: Int, completionTokens: Int)
    case done
    case ignore
}

enum OpenAILineParser {
    /// Parses one SSE line from the OpenAI Chat Completions stream.
    static func parse(line: String) -> OpenAILineResult {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return .ignore }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .ignore }
        // With `stream_options.include_usage`, the final chunk has empty `choices`
        // and a top-level `usage` object instead of a delta/finish_reason.
        if let usage = json["usage"] as? [String: Any],
           let promptTokens = usage["prompt_tokens"] as? Int,
           let completionTokens = usage["completion_tokens"] as? Int {
            return .usage(promptTokens: promptTokens, completionTokens: completionTokens)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first
        else { return .ignore }
        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return .token(content)
        }
        if let reason = first["finish_reason"] as? String {
            return .finish(reason: reason)
        }
        return .ignore
    }
}
