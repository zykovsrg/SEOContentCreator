import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: AppSection? = .contentPlan

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection ?? .contentPlan {
            case .contentPlan:
                ContentPlanView()
            case .knowledgeBase:
                KnowledgeBaseView()
            case .queue, .templates:
                let section = selection ?? .contentPlan
                ContentUnavailableView(
                    section.title,
                    systemImage: section.symbol,
                    description: Text("Раздел появится в следующем под-проекте.")
                )
            }
        }
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
        }
    }
}
