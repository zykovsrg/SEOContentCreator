import SwiftUI
import SwiftData
import AppKit

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: AppSection = .contentPlan

    var body: some View {
        Group {
            switch selection {
            case .contentPlan:   ContentPlanView()
            case .quickCheck:    QuickCheckView()
            case .templates:     TemplatesView()
            case .knowledgeBase: KnowledgeBaseView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SectionSwitcher(selection: $selection)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Настройки", systemImage: "gearshape")
                }
                .help("Настройки (⌘,)")
            }
        }
        .background(sectionShortcuts)
        .tint(.brandAccent)
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
            EditorDictionarySeeder.seedIfNeeded(in: context)
            SkillPresetSeeder.seedIfNeeded(in: context)
            ProductBlockSeeder.seedIfNeeded(in: context)
            ForbiddenPhraseSeeder.seedIfNeeded(in: context)
            SemanticReferenceSeeder.seedIfNeeded(in: context)
        }
    }

    /// Cmd+1…Cmd+4 select sections in the same order they appear in the header.
    private var sectionShortcuts: some View {
        ForEach(AppSection.allCases) { section in
            Button("") { selection = section }
                .keyboardShortcut(KeyEquivalent(section.shortcutKey), modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
