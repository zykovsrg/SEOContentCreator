import Testing
import Foundation
@testable import SEOContentCreator

struct KeychainServiceTests {
    private let account = "test-\(UUID().uuidString)"

    @Test func saveThenLoadReturnsValue() throws {
        try KeychainService.save(apiKey: "sk-test-123", account: account)
        defer { try? KeychainService.deleteAPIKey(account: account) }
        #expect(try KeychainService.loadAPIKey(account: account) == "sk-test-123")
    }

    @Test func loadMissingThrowsNotFound() {
        #expect(throws: KeychainService.KeychainError.notFound) {
            _ = try KeychainService.loadAPIKey(account: "missing-\(UUID().uuidString)")
        }
    }

    @Test func saveOverwritesExisting() throws {
        try KeychainService.save(apiKey: "first", account: account)
        try KeychainService.save(apiKey: "second", account: account)
        defer { try? KeychainService.deleteAPIKey(account: account) }
        #expect(try KeychainService.loadAPIKey(account: account) == "second")
    }
}
