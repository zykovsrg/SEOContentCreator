import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: AppSection = .contentPlan

    var body: some View {
        Group {
            switch selection {
            case .contentPlan:
                ContentPlanView()
            case .knowledgeBase:
                KnowledgeBaseView()
            case .templates:
                TemplatesView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Раздел", selection: $selection) {
                    ForEach(AppSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .background(sectionShortcuts)
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
            EditorDictionarySeeder.seedIfNeeded(in: context)
            SkillPresetSeeder.seedIfNeeded(in: context)
            ProductBlockSeeder.seedIfNeeded(in: context)
            ForbiddenPhraseSeeder.seedIfNeeded(in: context)
        }
    }

    /// Invisible buttons so Cmd+1/2/3 switch sections without a visible sidebar.
    private var sectionShortcuts: some View {
        Group {
            Button("") { selection = .contentPlan }.keyboardShortcut("1", modifiers: .command)
            Button("") { selection = .templates }.keyboardShortcut("2", modifiers: .command)
            Button("") { selection = .knowledgeBase }.keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
