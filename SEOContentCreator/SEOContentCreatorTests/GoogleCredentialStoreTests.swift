import Testing
import Foundation
@testable import SEOContentCreator

/// Родительский suite сериализует доступ к общему тестовому Keychain-хранилищу.
/// `.serialized` применяется рекурсивно, поэтому вложенные suites
/// (`CredentialStore`, `Auth`) не выполняются параллельно друг с другом и не
/// затирают сохранённые ключи/токены между тестами.
@Suite(.serialized)
struct GoogleKeychainTests {}

extension GoogleKeychainTests {
    @Suite(.serialized)
    struct CredentialStore {
        @Test func savesAndLoadsClientCredentials() throws {
            try? GoogleCredentialStore.deleteAll()
            try GoogleCredentialStore.saveClient(id: "cid.apps.googleusercontent.com", secret: "secret-x")
            #expect(GoogleCredentialStore.loadClientID() == "cid.apps.googleusercontent.com")
            #expect(GoogleCredentialStore.loadClientSecret() == "secret-x")
            #expect(GoogleCredentialStore.hasClient)
        }

        @Test func savesAndLoadsTokens() throws {
            try? GoogleCredentialStore.deleteAll()
            let tokens = GoogleTokens(accessToken: "at", refreshToken: "rt", expiry: Date(timeIntervalSince1970: 1000))
            try GoogleCredentialStore.saveTokens(tokens)
            let loaded = try #require(GoogleCredentialStore.loadTokens())
            #expect(loaded.accessToken == "at")
            #expect(loaded.refreshToken == "rt")
            #expect(loaded.expiry == Date(timeIntervalSince1970: 1000))
        }

        @Test func deleteAllClears() throws {
            try GoogleCredentialStore.saveClient(id: "c", secret: "s")
            try GoogleCredentialStore.deleteAll()
            #expect(!GoogleCredentialStore.hasClient)
            #expect(GoogleCredentialStore.loadTokens() == nil)
        }
    }
}
