import Foundation

/// Structured, per-generation description of an image prompt (FT-20260703-004).
/// `style` normally comes straight from `ImageStylePreset.styleText`; the rest
/// are filled in by the user (`subject` is seeded by `ImageSubjectSuggester`).
struct ImagePromptFields {
    var style: String = ""
    var scene: String = ""
    var subject: String = ""
    var lightingType: String = ""
    var lightingSource: String = ""
    var details: String = ""
    var camera: String = ""
    var mood: String = ""
    var aspectRatio: String = ""
}

enum ImageJSONPromptComposer {
    /// Serializes non-empty fields into a JSON object used as the final `prompt`
    /// sent to the image API. Empty fields are omitted rather than sent blank.
    static func compose(_ fields: ImagePromptFields) -> String {
        var object: [String: Any] = [:]
        func trimmed(_ value: String) -> String? {
            let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        if let v = trimmed(fields.style) { object["style"] = v }
        if let v = trimmed(fields.scene) { object["scene"] = v }
        if let v = trimmed(fields.subject) { object["subject"] = v }
        if let v = trimmed(fields.details) { object["details"] = v }
        if let v = trimmed(fields.camera) { object["camera"] = v }
        if let v = trimmed(fields.mood) { object["mood"] = v }
        if let v = trimmed(fields.aspectRatio) { object["aspect_ratio"] = v }

        var lighting: [String: String] = [:]
        if let v = trimmed(fields.lightingType) { lighting["type"] = v }
        if let v = trimmed(fields.lightingSource) { lighting["source"] = v }
        if !lighting.isEmpty { object["lighting"] = lighting }

        guard !object.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    /// Maps a known OpenAI image `size` string to a descriptive aspect ratio for the prompt.
    static func aspectRatio(forSize size: String) -> String {
        switch size {
        case "1024x1536": return "2:3"
        case "1536x1024": return "3:2"
        default: return "1:1"
        }
    }
}
