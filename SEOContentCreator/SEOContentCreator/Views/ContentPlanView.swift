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

    private var planHeader: some View {
        HStack(spacing: 12) {
            Text("Контент-план").font(.title2).bold()
            Text("\(visibleTopics.count) тем")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            Spacer()
            TextField("Поиск по темам", text: $filter.searchText)
                .textFieldStyle(.roundedBorder).frame(width: 200)
            Picker("Тип", selection: $filter.type) {
                Text("Все типы").tag(ArticleType?.none)
                ForEach(ArticleType.allCases) { Text($0.title).tag(ArticleType?.some($0)) }
            }
            .labelsHidden().fixedSize()
            Button { showingBrief = true } label: {
                Label("Новая тема", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    /// Column widths shared between the header row and each data row, so a
    /// custom `List` (no filler "zebra" rows past the data, unlike `Table`)
    /// still reads as an aligned table like the mockup.
    private enum Col {
        static let id: CGFloat = 50
        static let type: CGFloat = 110
        static let direction: CGFloat = 160
        static let stages: CGFloat = 110
        static let status: CGFloat = 150
        static let tokens: CGFloat = 80
    }

    private var planTableHeader: some View {
        HStack(spacing: 12) {
            Text("ID").frame(width: Col.id, alignment: .leading)
            Text("Тема").frame(maxWidth: .infinity, alignment: .leading)
            Text("Тип").frame(width: Col.type, alignment: .leading)
            Text("Направление").frame(width: Col.direction, alignment: .leading)
            Text("Этапы").frame(width: Col.stages, alignment: .leading)
            Text("Статус").frame(width: Col.status, alignment: .leading)
            Text("Токены").frame(width: Col.tokens, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder
    private func planRow(_ topic: Topic) -> some View {
        let status = TopicStatus.compute(for: topic)
        HStack(spacing: 12) {
            TextField("", text: Binding(
                get: { topic.externalID },
                set: { topic.externalID = $0 }
            ))
            .textFieldStyle(.plain)
            .frame(width: Col.id, alignment: .leading)
            Text(topic.title).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(topic.articleType.title).lineLimit(1)
                .frame(width: Col.type, alignment: .leading)
            Text(topic.direction?.title ?? "—").lineLimit(1)
                .frame(width: Col.direction, alignment: .leading)
            StageProgressDots(states: stageStates(for: topic).map(\.state))
                .frame(width: Col.stages, alignment: .leading)
            StatusPill(label: status.label, tone: status.tone)
                .frame(width: Col.status, alignment: .leading)
            Text(topic.totalTokenCost > 0 ? "\(topic.totalTokenCost)" : "—")
                .frame(width: Col.tokens, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
        .tag(topic.id)
    }

    private var planTable: some View {
        VStack(spacing: 0) {
            planHeader
            Divider()
            planTableHeader
            Divider()
            List(selection: $selection) {
                ForEach(visibleTopics) { topic in
                    planRow(topic)
                }
            }
            .listStyle(.plain)
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
        }
        .panelCard()
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground)
        .toolbar {
            ToolbarItem {
                Button {
                    if let id = selection, let t = topics.first(where: { $0.id == id }) { opened = t }
                } label: { Label("Открыть", systemImage: "arrow.right.circle") }
                .disabled(selection == nil)
            }
            ToolbarItem {
                Button { showingQuickCheck = true } label: {
                    Label("Быстрая проверка", systemImage: "checkmark.circle")
                }
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
