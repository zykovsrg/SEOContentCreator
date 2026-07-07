import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: AppSection? = .contentPlan

    private var groups: [(name: String, sections: [AppSection])] {
        [
            ("Работа", [.contentPlan]),
            ("Знания", [.templates, .knowledgeBase])
        ]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.sections) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .navigationTitle("SEO Content Creator")
            .background(sectionShortcuts)
        } detail: {
            switch selection ?? .contentPlan {
            case .contentPlan:   ContentPlanView()
            case .templates:     TemplatesView()
            case .knowledgeBase: KnowledgeBaseView()
            }
        }
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
            EditorDictionarySeeder.seedIfNeeded(in: context)
            SkillPresetSeeder.seedIfNeeded(in: context)
            ProductBlockSeeder.seedIfNeeded(in: context)
            ForbiddenPhraseSeeder.seedIfNeeded(in: context)
        }
    }

    /// Cmd+1/2/3 keep switching sections (now reflected by sidebar selection).
    private var sectionShortcuts: some View {
        Group {
            Button("") { selection = .contentPlan }.keyboardShortcut("1", modifiers: .command)
            Button("") { selection = .templates }.keyboardShortcut("2", modifiers: .command)
            Button("") { selection = .knowledgeBase }.keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
