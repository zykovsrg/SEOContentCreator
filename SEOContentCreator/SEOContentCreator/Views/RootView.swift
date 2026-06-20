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
            case .templates:
                TemplatesView()
            }
        }
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
        }
    }
}
