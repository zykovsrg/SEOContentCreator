import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case contentPlan, queue, templates, knowledgeBase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contentPlan:   return "Контент-план"
        case .queue:         return "Очередь"
        case .templates:     return "Шаблоны"
        case .knowledgeBase: return "База знаний"
        }
    }

    var symbol: String {
        switch self {
        case .contentPlan:   return "list.bullet.rectangle"
        case .queue:         return "clock"
        case .templates:     return "puzzlepiece"
        case .knowledgeBase: return "books.vertical"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: AppSection?

    var body: some View {
        List(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
        }
        .navigationTitle("SEOContentCreator")
    }
}
