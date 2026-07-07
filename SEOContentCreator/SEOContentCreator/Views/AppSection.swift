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

    var systemImage: String {
        switch self {
        case .contentPlan:   return "list.bullet.rectangle"
        case .templates:     return "doc.text"
        case .knowledgeBase: return "books.vertical"
        }
    }

    /// Sidebar group heading this section belongs to.
    var group: String {
        switch self {
        case .contentPlan:            return "Работа"
        case .templates, .knowledgeBase: return "Знания"
        }
    }
}
