import Foundation

struct GoogleDocsClient {
    enum DocsError: Error, Equatable, LocalizedError {
        case unauthorized
        case http(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Google отклонил запрос (401). Войдите в Google заново в Настройках."
            case .http(let c): return "Ошибка Google API (HTTP \(c)). Попробуйте позже."
            case .badResponse: return "Не удалось разобрать ответ Google."
            }
        }
    }

    let session: URLSession
    let tokenProvider: () async throws -> String
    let maxAttempts: Int

    init(session: URLSession = .shared,
         tokenProvider: @escaping () async throws -> String,
         maxAttempts: Int = 4) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.maxAttempts = maxAttempts
    }

    func createDocument(title: String) async throws -> String {
        let url = URL(string: "https://docs.googleapis.com/v1/documents")!
        let data = try await send(url: url, method: "POST", json: ["title": title])
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["documentId"] as? String else { throw DocsError.badResponse }
        return id
    }

    func batchUpdate(docID: String, requests: [[String: Any]]) async throws {
        let url = URL(string: "https://docs.googleapis.com/v1/documents/\(docID):batchUpdate")!
        _ = try await send(url: url, method: "POST", json: ["requests": requests])
    }

    func clearBody(docID: String) async throws {
        let endIndex = try await documentBodyEndIndex(docID: docID)
        guard endIndex > 2 else { return }
        try await batchUpdate(docID: docID, requests: [[
            "deleteContentRange": [
                "range": ["startIndex": 1, "endIndex": endIndex - 1]
            ]
        ]])
    }

    func documentBodyEndIndex(docID: String) async throws -> Int {
        let getURL = URL(string: "https://docs.googleapis.com/v1/documents/\(docID)")!
        let data = try await send(url: getURL, method: "GET", json: nil)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = obj["body"] as? [String: Any],
              let content = body["content"] as? [[String: Any]] else { throw DocsError.badResponse }
        return content.compactMap { $0["endIndex"] as? Int }.max() ?? 1
    }

    func findOrCreateFolder(name: String) async throws -> String {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let q = "mimeType='application/vnd.google-apps.folder' and name='\(name)' and trashed=false"
        comps.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "fields", value: "files(id,name)")]
        let data = try await send(url: comps.url!, method: "GET", json: nil)
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = obj["files"] as? [[String: Any]],
           let id = files.first?["id"] as? String {
            return id
        }
        let createURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
        let created = try await send(url: createURL, method: "POST",
            json: ["name": name, "mimeType": "application/vnd.google-apps.folder"])
        guard let obj = try? JSONSerialization.jsonObject(with: created) as? [String: Any],
              let id = obj["id"] as? String else { throw DocsError.badResponse }
        return id
    }

    func moveToFolder(fileID: String, folderID: String) async throws {
        // Сначала узнаём текущих родителей файла, чтобы убрать его именно
        // оттуда (жёсткий алиас "root" срабатывает не всегда — документ,
        // созданный через Docs API, остаётся в корне «Мой диск»).
        var getComps = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        getComps.queryItems = [URLQueryItem(name: "fields", value: "parents")]
        let data = try await send(url: getComps.url!, method: "GET", json: nil)
        let parents = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["parents"] as? [String] ?? []

        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        var items = [URLQueryItem(name: "addParents", value: folderID)]
        let toRemove = parents.filter { $0 != folderID }
        if !toRemove.isEmpty {
            items.append(URLQueryItem(name: "removeParents", value: toRemove.joined(separator: ",")))
        }
        comps.queryItems = items
        _ = try await send(url: comps.url!, method: "PATCH", json: [:])
    }

    static func documentURL(id: String) -> String {
        "https://docs.google.com/document/d/\(id)/edit"
    }

    /// Escapes a value for use inside single quotes in a Drive `q` query.
    static func escapeQueryValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "'", with: "\\'")
    }

    static func folderURL(id: String) -> String {
        "https://drive.google.com/drive/folders/\(id)"
    }

    static func folderID(fromURL url: String) -> String? {
        guard let range = url.range(of: "/drive/folders/") else { return nil }
        let id = url[range.upperBound...].components(separatedBy: "/").first
        return (id?.isEmpty == false) ? id : nil
    }

    /// Grants "anyone with the link" access. A permission set on a folder cascades
    /// to everything inside it, so sharing the topic folder covers its images.
    /// Repeat calls are safe: Drive keeps one `anyone` permission per file and
    /// updates its role instead of adding duplicates.
    /// Works under the `drive.file` scope because the app created these files.
    func shareWithAnyoneWithLink(fileID: String, role: String) async throws {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)/permissions")!
        _ = try await send(url: url, method: "POST", json: ["role": role, "type": "anyone"])
    }

    /// Finds or creates a folder INSIDE the given parent (unlike the root-level
    /// `findOrCreateFolder(name:)` above).
    func findOrCreateFolder(name: String, parentID: String) async throws -> String {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let escaped = Self.escapeQueryValue(name)
        let q = "mimeType='application/vnd.google-apps.folder' and name='\(escaped)' and '\(parentID)' in parents and trashed=false"
        comps.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "fields", value: "files(id,name)")]
        let data = try await send(url: comps.url!, method: "GET", json: nil)
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = obj["files"] as? [[String: Any]],
           let id = files.first?["id"] as? String {
            return id
        }
        let createURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
        let created = try await send(url: createURL, method: "POST",
            json: ["name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [parentID]])
        guard let obj = try? JSONSerialization.jsonObject(with: created) as? [String: Any],
              let id = obj["id"] as? String else { throw DocsError.badResponse }
        return id
    }

    /// Multipart body for `uploadType=multipart` (metadata JSON + file bytes).
    static func multipartBody(metadataJSON: Data, fileData: Data, mimeType: String, boundary: String) -> Data {
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        add("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadataJSON)
        add("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        add("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Uploads a file into the given folder. Returns the created file's ID.
    func uploadFile(name: String, data: Data, mimeType: String, parentID: String) async throws -> String {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!
        let boundary = "seo-content-creator-\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parentID]])
        let body = Self.multipartBody(metadataJSON: metadata, fileData: data, mimeType: mimeType, boundary: boundary)
        let response = try await send(url: url, method: "POST", body: body,
                                      contentType: "multipart/related; boundary=\(boundary)")
        guard let obj = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let id = obj["id"] as? String else { throw DocsError.badResponse }
        return id
    }

    private func send(url: URL, method: String, json: [String: Any]?) async throws -> Data {
        var body: Data?
        if let json { body = try JSONSerialization.data(withJSONObject: json) }
        return try await send(url: url, method: method, body: body,
                              contentType: json == nil ? nil : "application/json")
    }

    private func send(url: URL, method: String, body: Data?, contentType: String?) async throws -> Data {
        var lastError: Error = DocsError.badResponse
        for attempt in 0..<maxAttempts {
            do {
                let token = try await tokenProvider()
                var req = URLRequest(url: url)
                req.httpMethod = method
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
                req.httpBody = body
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                switch code {
                case 200...299: return data
                case 401: throw DocsError.unauthorized
                case 429, 500...599:
                    lastError = DocsError.http(code)
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 0.5 * 1_000_000_000))
                    continue
                default: throw DocsError.http(code)
                }
            } catch let e as DocsError where e == .unauthorized {
                throw e
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 0.5 * 1_000_000_000))
            }
        }
        throw lastError
    }
}
