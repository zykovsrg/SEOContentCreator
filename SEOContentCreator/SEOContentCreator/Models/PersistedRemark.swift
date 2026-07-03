import Foundation
import SwiftData

enum RemarkDecisionStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

/// Durable copy of a checking-stage `Remark`, so a review in progress survives
/// an app restart (see FT-20260702-011). `uuid` mirrors `Remark.id` so the
/// transient struct used by the UI and this record can be matched up.
@Model
final class PersistedRemark {
    var uuid: UUID
    var category: String
    var quote: String
    var suggestion: String
    var explanation: String
    var statusRaw: String
    var createdAt: Date

    @Relationship var job: GenerationJob?

    init(remark: Remark, status: RemarkDecisionStatus = .pending) {
        self.uuid = remark.id
        self.category = remark.category
        self.quote = remark.quote
        self.suggestion = remark.suggestion
        self.explanation = remark.explanation
        self.statusRaw = status.rawValue
        self.createdAt = .now
    }

    var status: RemarkDecisionStatus {
        get { RemarkDecisionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var asRemark: Remark {
        Remark(id: uuid, category: category, quote: quote, suggestion: suggestion, explanation: explanation)
    }
}
