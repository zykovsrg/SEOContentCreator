import Foundation

/// Parses the `{"suggestion":"..."}` JSON response from a remark redo call.
enum RemarkRedoParser {
    private struct Wrapper: Codable { let suggestion: String }

    static func parse(rawText: String) -> String? {
        guard let json = extractJSON(from: rawText),
              let data = json.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data)
        else { return nil }
        return wrapper.suggestion
    }

    private static func extractJSON(from text: String) -> String? {
        if let fence = text.range(of: "```json"),
           let end = text.range(of: "```", range: fence.upperBound..<text.endIndex) {
            return String(text[fence.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last {
            return String(text[first...last])
        }
        return nil
    }
}
