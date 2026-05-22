import SwiftUI

struct RootView: View {
    @State private var selection: AppSection? = .contentPlan

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection ?? .contentPlan {
            case .contentPlan:
                ContentPlanView()
            case .queue, .templates, .knowledgeBase:
                let section = selection ?? .contentPlan
                ContentUnavailableView(
                    section.title,
                    systemImage: section.symbol,
                    description: Text("Раздел появится в следующем под-проекте.")
                )
            }
        }
    }
}
