import Foundation

struct StageOutput {
    var body: String
    var h1: String?
    var seoTitle: String?
    var seoDescription: String?
    var embeddedQueries: [String]
    var notes: String?
}

enum StageOutputParser {
    /// For semanticsInText, the model appends a ```json {...}``` block with metadata.
    /// Other stages return plain body text.
    static func parse(rawText: String, stage: PipelineStage) -> StageOutput {
        guard stage == .semanticsInText else {
            return StageOutput(body: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
                               h1: nil, seoTitle: nil, seoDescription: nil,
                               embeddedQueries: [], notes: nil)
        }

        guard let range = rawText.range(of: "```json"),
              let endRange = rawText.range(of: "```", range: range.upperBound..<rawText.endIndex) else {
            return StageOutput(body: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
                               h1: nil, seoTitle: nil, seoDescription: nil,
                               embeddedQueries: [], notes: nil)
        }

        let body = String(rawText[rawText.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = String(rawText[range.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return StageOutput(body: body, h1: nil, seoTitle: nil, seoDescription: nil,
                               embeddedQueries: [], notes: nil)
        }

        return StageOutput(
            body: body,
            h1: json["h1"] as? String,
            seoTitle: json["seoTitle"] as? String,
            seoDescription: json["seoDescription"] as? String,
            embeddedQueries: json["embeddedQueries"] as? [String] ?? [],
            notes: json["notes"] as? String
        )
    }
}
