import Foundation

enum ImageResponseParser {
    static func parse(_ data: Data) throws -> Data {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let array = object["data"] as? [[String: Any]],
            let b64 = array.first?["b64_json"] as? String,
            let bytes = Data(base64Encoded: b64)
        else {
            throw OpenAIClient.OpenAIError.badResponse
        }
        return bytes
    }
}
