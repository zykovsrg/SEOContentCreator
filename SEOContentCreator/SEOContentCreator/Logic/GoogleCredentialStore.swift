import Foundation
import Security

enum GoogleCredentialStore {
    static let serviceName = "SEOContentCreator.Google"

    private static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainService.KeychainError.unexpectedStatus(status) }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveClient(id: String, secret: String) throws {
        try save(id, account: "clientID")
        try save(secret, account: "clientSecret")
    }
    static func loadClientID() -> String? { load(account: "clientID") }
    static func loadClientSecret() -> String? { load(account: "clientSecret") }
    static var hasClient: Bool { loadClientID() != nil && loadClientSecret() != nil }

    static func saveTokens(_ tokens: GoogleTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try save(String(decoding: data, as: UTF8.self), account: "tokens")
    }
    static func loadTokens() -> GoogleTokens? {
        guard let raw = load(account: "tokens"), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }
    static var isSignedIn: Bool { loadTokens() != nil }

    static func deleteAll() throws {
        delete(account: "clientID")
        delete(account: "clientSecret")
        delete(account: "tokens")
    }
}
