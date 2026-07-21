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

    /// Cmd+<key> that selects this section. Follows the header order, so the
    /// number the user presses matches what they see left to right.
    var shortcutKey: Character {
        switch self {
        case .contentPlan:   return "1"
        case .quickCheck:    return "2"
        case .templates:     return "3"
        case .knowledgeBase: return "4"
        }
    }

    /// Section for a Cmd+<key> press, or `nil` for keys we do not bind.
    static func section(forShortcutKey key: Character) -> AppSection? {
        allCases.first { $0.shortcutKey == key }
    }

    /// The header draws a divider before this section, replacing the old
    /// "Работа" / "Знания" sidebar group headings.
    var startsNewGroup: Bool {
        self == .templates
    }
}
