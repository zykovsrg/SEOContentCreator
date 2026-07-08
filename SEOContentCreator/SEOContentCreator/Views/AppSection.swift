import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case contentPlan, quickCheck, templates, knowledgeBase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contentPlan:   return "Контент-план"
        case .quickCheck:    return "Быстрая проверка"
        case .templates:     return "Шаблоны"
        case .knowledgeBase: return "База знаний"
        }
    }

    var systemImage: String {
        switch self {
        case .contentPlan:   return "list.bullet.rectangle"
        case .quickCheck:    return "checkmark.circle"
        case .templates:     return "doc.text"
        case .knowledgeBase: return "books.vertical"
        }
    }

    /// Sidebar group heading this section belongs to.
    var group: String {
        switch self {
        case .contentPlan, .quickCheck: return "Работа"
        case .templates, .knowledgeBase: return "Знания"
        }
    }
}
