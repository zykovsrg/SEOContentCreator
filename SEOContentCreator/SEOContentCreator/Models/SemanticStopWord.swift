import Foundation
import SwiftData

/// A word that removes a query from the funnel at the rule layer.
/// Global across topics — see the design doc's note on drift.
@Model
final class SemanticStopWord {
    var uuid: UUID
    var text: String
    var isEnabled: Bool
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(text: String, order: Int, isEnabled: Bool = true) {
        self.uuid = UUID()
        self.text = text
        self.isEnabled = isEnabled
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
