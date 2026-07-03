import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case contentPlan, templates, knowledgeBase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contentPlan:   return "Контент-план"
        case .templates:     return "Шаблоны"
        case .knowledgeBase: return "База знаний"
        }
    }
}
