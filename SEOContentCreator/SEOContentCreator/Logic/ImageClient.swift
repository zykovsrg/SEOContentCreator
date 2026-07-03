import Foundation

struct ImageClient {
    let session: URLSession
    let generationsEndpoint: URL
    let editsEndpoint: URL

    init(
        session: URLSession = .shared,
        generationsEndpoint: URL = URL(string: "https://api.openai.com/v1/images/generations")!,
        editsEndpoint: URL = URL(string: "https://api.openai.com/v1/images/edits")!
    ) {
        self.session = session
        self.generationsEndpoint = generationsEndpoint
        self.editsEndpoint = editsEndpoint
    }

    static func usesEdits(referenceCount: Int) -> Bool { referenceCount > 0 }

    func generate(
        apiKey: String, prompt: String, model: String,
        size: String, quality: String, references: [Data]
    ) async throws -> Data {
        let request = Self.usesEdits(referenceCount: references.count)
            ? try makeEditsRequest(apiKey: apiKey, prompt: prompt, model: model, size: size, quality: quality, images: references)
            : try makeGenerationsRequest(apiKey: apiKey, prompt: prompt, model: model, size: size, quality: quality)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 401: throw OpenAIClient.OpenAIError.unauthorized
            case 429: throw OpenAIClient.OpenAIError.rateLimited
            default: throw OpenAIClient.OpenAIError.http(http.statusCode, message: OpenAIClient.extractErrorMessage(from: data))
            }
        }
        return try ImageResponseParser.parse(data)
    }

    private func makeGenerationsRequest(
        apiKey: String, prompt: String, model: String, size: String, quality: String
    ) throws -> URLRequest {
        var request = URLRequest(url: generationsEndpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "n": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func makeEditsRequest(
        apiKey: String, prompt: String, model: String, size: String, quality: String, images: [Data]
    ) throws -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: editsEndpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", model)
        appendField("prompt", prompt)
        appendField("size", size)
        appendField("quality", quality)
        appendField("n", "1")

        for (index, image) in images.enumerated() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image[]\"; filename=\"image\(index).png\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            body.append(image)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return request
    }
}
