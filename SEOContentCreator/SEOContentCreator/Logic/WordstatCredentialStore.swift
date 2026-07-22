import Foundation

/// Stores Wordstat credentials for both providers alongside the OpenAI key,
/// using the same Keychain path. Reuses `KeychainService`'s existing
/// `save(apiKey:account:)` / `loadAPIKey(account:)` pair — despite the
/// `apiKey` parameter name, they are generic secret-string storage keyed by
/// `account`, so adding near-duplicate overloads here would just be
/// redundant Keychain code. `folderID` is not a secret, but storing it
/// alongside the real credentials keeps this to one storage mechanism
/// instead of adding separate UserDefaults plumbing for one value.
enum WordstatCredentialStore {
    static func saveLegacyToken(_ token: String) throws {
        try KeychainService.save(apiKey: token, account: "wordstatLegacyToken")
    }

    static func loadLegacyToken() throws -> String {
        try KeychainService.loadAPIKey(account: "wordstatLegacyToken")
    }

    static func saveCloudAPIKey(_ key: String) throws {
        try KeychainService.save(apiKey: key, account: "wordstatCloudAPIKey")
    }

    static func loadCloudAPIKey() throws -> String {
        try KeychainService.loadAPIKey(account: "wordstatCloudAPIKey")
    }

    static func saveCloudFolderID(_ folderID: String) throws {
        try KeychainService.save(apiKey: folderID, account: "wordstatCloudFolderID")
    }

    static func loadCloudFolderID() throws -> String {
        try KeychainService.loadAPIKey(account: "wordstatCloudFolderID")
    }
}
