import Foundation
import SwiftData

enum SemanticAgentRecommendation: String, Codable, CaseIterable {
    case include
    case exclude
    case none

    var label: String {
        switch self {
        case .include: return "Включить"
        case .exclude: return "Не включать"
        case .none: return "Нет рекомендации"
        }
    }
}

enum SemanticUserDecision: String, Codable, CaseIterable {
    case pending
    case accepted
    case rejected
    case required

    var label: String {
        switch self {
        case .pending: return "Ожидает решения"
        case .accepted: return "Принято"
        case .rejected: return "Отклонено"
        case .required: return "Обязательно"
        }
    }
}

enum SemanticReasonCategory: String, Codable, CaseIterable {
    case none
    case junk
    case offTopic
    case cannibalization
    case lowQuality
    case tooBroad
    case wrongIntent
    case other

    var label: String {
        switch self {
        case .none: return "Нет"
        case .junk: return "Мусор"
        case .offTopic: return "Не по теме"
        case .cannibalization: return "Каннибализация"
        case .lowQuality: return "Низкое качество"
        case .tooBroad: return "Слишком общий"
        case .wrongIntent: return "Не тот интент"
        case .other: return "Другое"
        }
    }
}

enum SemanticCannibalizationRisk: String, Codable, CaseIterable {
    case none
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .none: return "Нет"
        case .low: return "Низкий"
        case .medium: return "Средний"
        case .high: return "Высокий"
        }
    }
}

@Model
final class SemanticKeyword {
    var uuid: UUID
    var text: String
    var frequency: Int?
    var agentRecommendationRaw: String
    var userDecisionRaw: String
    var reasonCategoryRaw: String
    var explanation: String
    var cannibalizationRiskRaw: String
    var cannibalizationURL: String?
    var cannibalizationTitle: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship var topic: Topic?

    init(
        text: String,
        frequency: Int? = nil,
        agentRecommendation: SemanticAgentRecommendation = .none,
        userDecision: SemanticUserDecision = .pending,
        reasonCategory: SemanticReasonCategory = .none,
        explanation: String = "",
        cannibalizationRisk: SemanticCannibalizationRisk = .none,
        cannibalizationURL: String? = nil,
        cannibalizationTitle: String? = nil
    ) {
        self.uuid = UUID()
        self.text = text
        self.frequency = frequency
        self.agentRecommendationRaw = agentRecommendation.rawValue
        self.userDecisionRaw = userDecision.rawValue
        self.reasonCategoryRaw = reasonCategory.rawValue
        self.explanation = explanation
        self.cannibalizationRiskRaw = cannibalizationRisk.rawValue
        self.cannibalizationURL = cannibalizationURL
        self.cannibalizationTitle = cannibalizationTitle
        self.createdAt = .now
        self.updatedAt = .now
    }

    var agentRecommendation: SemanticAgentRecommendation {
        get { SemanticAgentRecommendation(rawValue: agentRecommendationRaw) ?? .none }
        set {
            agentRecommendationRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var userDecision: SemanticUserDecision {
        get { SemanticUserDecision(rawValue: userDecisionRaw) ?? .pending }
        set {
            userDecisionRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var reasonCategory: SemanticReasonCategory {
        get { SemanticReasonCategory(rawValue: reasonCategoryRaw) ?? .none }
        set {
            reasonCategoryRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var cannibalizationRisk: SemanticCannibalizationRisk {
        get { SemanticCannibalizationRisk(rawValue: cannibalizationRiskRaw) ?? .none }
        set {
            cannibalizationRiskRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
