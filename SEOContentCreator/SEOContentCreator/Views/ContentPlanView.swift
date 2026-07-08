import SwiftUI
import SwiftData

struct ContentPlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.updatedAt, order: .reverse) private var topics: [Topic]

    @State private var filter = ContentPlanFilter()
    @State private var selection: Topic.ID?
    @State private var showingBrief = false
    @State private var showingQuickCheck = false
    @State private var editingTopic: Topic?
    @State private var opened: Topic?
    @State private var topicPendingDeletion: Topic?

    private var visibleTopics: [Topic] { filter.apply(to: topics) }

    private func stageStates(for topic: Topic) -> [(stage: PipelineStage, state: StageState)] {
        let hasImages = !topic.images.filter { !$0.isArchived }.isEmpty
        let hasRecs = !topic.promptRecommendations.isEmpty
        return StagePipeline.states { stage in
            StageProgress.isCompleted(
                stage, versions: topic.versions, structureText: topic.structureText,
                hasImages: hasImages, hasPromptRecommendations: hasRecs
            )
        }
    }

    var body: some View {
        if let opened {
            TopicWorkspaceView(topic: opened, onBack: { self.opened = nil })
        } else {
            planTable
        }
    }

    private var planTable: some View {
        Table(visibleTopics, selection: $selection) {
            TableColumn("ID") { topic in
                TextField("", text: Binding(
                    get: { topic.externalID },
                    set: { topic.externalID = $0 }
                ))
                .textFieldStyle(.plain)
            }
            .width(60)
            TableColumn("Тема") { Text($0.title) }
            TableColumn("Тип") { Text($0.articleType.title) }
            TableColumn("Направление") { Text($0.direction?.title ?? "—") }
            TableColumn("Этапы") { topic in
                StageProgressDots(states: stageStates(for: topic).map(\.state))
            }
            .width(110)
            TableColumn("Статус") { topic in
                let status = TopicStatus.compute(for: topic)
                StatusPill(label: status.label, tone: status.tone)
            }
            TableColumn("Токены") { Text($0.totalTokenCost > 0 ? "\($0.totalTokenCost)" : "—") }
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: Topic.ID.self) { ids in
            if let id = ids.first, let t = topics.first(where: { $0.id == id }) {
                Button("Открыть") { opened = t }
                Button("Редактировать") { editingTopic = t }
                Button("Удалить", role: .destructive) { topicPendingDeletion = t }
            }
        } primaryAction: { ids in
            if let id = ids.first, let t = topics.first(where: { $0.id == id }) { opened = t }
        }
        .panelCard()
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground)
        .searchable(text: $filter.searchText, prompt: "Поиск по темам")
        .toolbar {
            ToolbarItem {
                Button {
                    if let id = selection, let t = topics.first(where: { $0.id == id }) { opened = t }
                } label: { Label("Открыть", systemImage: "arrow.right.circle") }
                .disabled(selection == nil)
            }
            ToolbarItem {
                Picker("Тип", selection: $filter.type) {
                    Text("Все типы").tag(ArticleType?.none)
                    ForEach(ArticleType.allCases) { Text($0.title).tag(ArticleType?.some($0)) }
                }
            }
            ToolbarItem {
                Button { showingQuickCheck = true } label: {
                    Label("Быстрая проверка", systemImage: "checkmark.circle")
                }
            }
            ToolbarItem {
                Button { showingBrief = true } label: { Label("Новая тема", systemImage: "plus") }
            }
        }
        .navigationTitle("Контент-план")
        .sheet(isPresented: $showingBrief) { BriefView(topic: nil) }
        .sheet(item: $editingTopic) { BriefView(topic: $0) }
        .sheet(isPresented: $showingQuickCheck) { QuickCheckSheet() }
        .confirmationDialog("Удалить тему?", isPresented: Binding(
            get: { topicPendingDeletion != nil },
            set: { if !$0 { topicPendingDeletion = nil } }
        )) {
            Button("Удалить", role: .destructive) {
                if let topicPendingDeletion { context.delete(topicPendingDeletion) }
                topicPendingDeletion = nil
            }
            Button("Отмена", role: .cancel) { topicPendingDeletion = nil }
        } message: {
            Text("Тема и связанные версии, логи и изображения будут удалены.")
        }
    }
}
