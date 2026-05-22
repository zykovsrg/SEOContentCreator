import SwiftUI
import SwiftData

struct ContentPlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.updatedAt, order: .reverse) private var topics: [Topic]

    @State private var filter = ContentPlanFilter()
    @State private var selection: Topic.ID?
    @State private var showingBrief = false
    @State private var editingTopic: Topic?

    private var visibleTopics: [Topic] { filter.apply(to: topics) }

    var body: some View {
        Table(visibleTopics, selection: $selection) {
            TableColumn("Тема") { Text($0.title) }
            TableColumn("Тип") { Text($0.articleType.title) }
            TableColumn("Направление") { Text($0.direction.isEmpty ? "—" : $0.direction) }
            TableColumn("Статус") { Text(TopicStatus.compute(for: $0).label) }
        }
        .contextMenu(forSelectionType: Topic.ID.self) { ids in
            if let id = ids.first, let t = topics.first(where: { $0.id == id }) {
                Button("Редактировать") { editingTopic = t }
                Button("Удалить", role: .destructive) { context.delete(t) }
            }
        }
        .searchable(text: $filter.searchText, prompt: "Поиск по темам")
        .toolbar {
            ToolbarItem {
                Picker("Тип", selection: $filter.type) {
                    Text("Все типы").tag(ArticleType?.none)
                    ForEach(ArticleType.allCases) { Text($0.title).tag(ArticleType?.some($0)) }
                }
            }
            ToolbarItem {
                Button { showingBrief = true } label: { Label("Новая тема", systemImage: "plus") }
            }
        }
        .navigationTitle("Контент-план")
        .sheet(isPresented: $showingBrief) { BriefView(topic: nil) }
        .sheet(item: $editingTopic) { BriefView(topic: $0) }
    }
}
