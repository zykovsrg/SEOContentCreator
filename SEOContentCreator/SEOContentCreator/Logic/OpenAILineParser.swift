import Foundation

enum OpenAILineResult: Equatable {
    case token(String)
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return .ignore }
        return .token(content)
    }
}
