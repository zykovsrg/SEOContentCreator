import Foundation
import SwiftData

/// Where a query left the funnel.
enum SemanticFunnelLayer: String, Codable, CaseIterable {
    case raw
    case droppedByRules
    case droppedByRelevance
    case droppedByCannibalization
    case survived

    var label: String {
        switch self {
        case .raw: return "Собрано из Wordstat"
        case .droppedByRules: return "Отсеяно правилами"
        case .droppedByRelevance: return "Отсеяно по релевантности"
        case .droppedByCannibalization: return "Отсеяно по каннибализации"
        case .survived: return "Прошло в семантику"
        }
    }
}

/// One row of the collection run journal. Kept separate from `SemanticKeyword`
/// so a several-hundred-phrase raw pool does not inflate topic semantics.
@Model
final class SemanticFunnelEntry {
    var uuid: UUID
    var text: String
    var frequency: Int?
    var layerRaw: String
    var reason: String
    var runID: UUID
    var createdAt: Date

    @Relationship var topic: Topic?

    init(text: String, frequency: Int?, layer: SemanticFunnelLayer, reason: String, runID: UUID) {
        self.uuid = UUID()
        self.text = text
        self.frequency = frequency
        self.layerRaw = layer.rawValue
        self.reason = reason
        self.runID = runID
        self.createdAt = .now
    }

    var layer: SemanticFunnelLayer {
        get { SemanticFunnelLayer(rawValue: layerRaw) ?? .raw }
        set { layerRaw = newValue.rawValue }
    }
}
