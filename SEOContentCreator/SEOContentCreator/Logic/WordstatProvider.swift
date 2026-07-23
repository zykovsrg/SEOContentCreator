import Foundation

/// One phrase returned by Wordstat, with its monthly impression count.
struct WordstatPhrase: Codable, Equatable, Sendable {
    var text: String
    var frequency: Int
}

/// Pulls including-phrases for one seed. Injected so layers stay testable offline.
typealias WordstatProvider = @Sendable (_ seed: String) async throws -> [WordstatPhrase]

/// Which Wordstat backend the app calls. Stored in @AppStorage so the user
/// can flip it without touching Keychain data for the other one.
enum WordstatProviderKind: String, CaseIterable {
    case legacy
    case cloud

    var label: String {
        switch self {
        case .legacy: return "Старый API (OAuth-токен)"
        case .cloud: return "Yandex Cloud (API-ключ + folderId)"
        }
    }
}
