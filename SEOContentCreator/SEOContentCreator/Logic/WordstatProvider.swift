import Foundation

/// One phrase returned by Wordstat, with its monthly impression count.
struct WordstatPhrase: Equatable, Sendable {
    var text: String
    var frequency: Int
}

/// Pulls including-phrases for one seed. Injected so layers stay testable offline.
typealias WordstatProvider = @Sendable (_ seed: String) async throws -> [WordstatPhrase]
