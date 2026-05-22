import Foundation

struct Remark: Codable, Identifiable {
    var id = UUID()
    var category: String
    var quote: String
    var suggestion: String
    var explanation: String

    enum CodingKeys: String, CodingKey {
        case category, quote, suggestion, explanation
    }
}

enum RemarksParser {
    private struct Wrapper: Codable { let remarks: [Remark] }

    /// Extracts a JSON object (from a ```json fence or the first {...}) and decodes `{"remarks":[…]}`.
    /// Returns [] on missing or malformed JSON.
    static func parse(rawText: String) -> [Remark] {
        guard let json = extractJSON(from: rawText),
              let data = json.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data)
        else { return [] }
        return wrapper.remarks
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
