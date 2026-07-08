import SwiftUI
import SwiftData
import AppKit

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: AppSection? = .contentPlan

    private var groups: [(name: String, sections: [AppSection])] {
        [
            ("Работа", [.contentPlan, .quickCheck]),
            ("Знания", [.templates, .knowledgeBase])
        ]
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
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
                .listStyle(.sidebar)

                Divider().padding(.horizontal, 12)
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Настройки", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .navigationTitle("SEO Content Creator")
            .background(sectionShortcuts)
        } detail: {
            switch selection ?? .contentPlan {
            case .contentPlan:   ContentPlanView()
            case .quickCheck:    QuickCheckView()
            case .templates:     TemplatesView()
            case .knowledgeBase: KnowledgeBaseView()
            }
        }
        .tint(.brandAccent)
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
