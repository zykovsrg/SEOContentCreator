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
        let getURL = URL(string: "https://docs.googleapis.com/v1/documents/\(docID)")!
        let data = try await send(url: getURL, method: "GET", json: nil)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = obj["body"] as? [String: Any],
              let content = body["content"] as? [[String: Any]],
              let endIndex = content.compactMap({ $0["endIndex"] as? Int }).max(),
              endIndex > 2 else { return }
        try await batchUpdate(docID: docID, requests: [[
            "deleteContentRange": [
                "range": ["startIndex": 1, "endIndex": endIndex - 1]
            ]
        ]])
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

    private func send(url: URL, method: String, json: [String: Any]?) async throws -> Data {
        var lastError: Error = DocsError.badResponse
        for attempt in 0..<maxAttempts {
            do {
                let token = try await tokenProvider()
                var req = URLRequest(url: url)
                req.httpMethod = method
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let json {
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: json)
                }
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
