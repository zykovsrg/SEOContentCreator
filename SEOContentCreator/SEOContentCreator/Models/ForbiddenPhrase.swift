import Foundation
import SwiftData

@Model
final class ForbiddenPhrase {
    var uuid: UUID
    /// Предложение или формулировка, которую нельзя использовать.
    var phrase: String
    /// В чём проблема.
    var problem: String
    /// Как можно заменить.
    var replacement: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(phrase: String, problem: String, replacement: String, order: Int) {
        self.uuid = UUID()
        self.phrase = phrase
        self.problem = problem
        self.replacement = replacement
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
