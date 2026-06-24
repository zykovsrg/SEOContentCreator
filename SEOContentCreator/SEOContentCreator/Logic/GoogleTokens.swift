import Foundation

struct GoogleTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date

    var isExpired: Bool { Date() >= expiry.addingTimeInterval(-60) }
}
