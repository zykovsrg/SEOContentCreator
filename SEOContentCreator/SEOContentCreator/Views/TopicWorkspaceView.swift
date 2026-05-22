import SwiftUI
import SwiftData

struct TopicWorkspaceView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    var onBack: () -> Void

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @State private var selectedStage: PipelineStage = .draft
    @State private var executor: StageExecutor?
    @State private var comparisonText: String?     // left column (previous current)
    @State private var showVersions = false
    @State private var showLog = false
    @State private var showProductBlocks = false
    @State private var showSemantics = false
    @State private var showPartialAccept = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            StageBarView(selectedStage: $selectedStage, topic: topic)
                .padding(.vertical, 8)
            Divider()
            SideBySideView(
                leftText: comparisonText ?? topic.currentVersion?.text,
                rightText: rightText,
                isStreaming: executor?.isRunning ?? false
            )
            Divider()
            AcceptRejectBar(
                canAct: pendingGeneratedVersion != nil,
                onAcceptAll: acceptAll,
                onAcceptPartial: { showPartialAccept = true },
                onReject: reject
            )
        }
        .navigationTitle(topic.title)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showVersions) {
            VersionLaneView(topic: topic) { comparisonText = $0.text }
        }
        .sheet(isPresented: $showLog) { JobLogView(topic: topic) }
        .sheet(isPresented: $showProductBlocks) {
            ProductBlocksSheet(topic: topic) { runStage(.productBlocks, blocks: $0) }
        }
        .sheet(isPresented: $showSemantics) { SemanticsEditorSheet(topic: topic) }
        .sheet(isPresented: $showPartialAccept) {
            if let pending = pendingGeneratedVersion, let base = comparisonText {
                PartialAcceptSheet(oldText: base, newText: pending.text) { acceptedIndices in
                    applyPartial(base: base, generated: pending, indices: acceptedIndices)
                }
            }
        }
        .onAppear { if executor == nil { executor = .live(model: model) } }
    }

    private var rightText: String? {
        if let executor, executor.isRunning { return executor.streamingText }
        return pendingGeneratedVersion?.text
    }

    /// The most recent generated version that hasn't been archived (awaiting accept/reject).
    private var pendingGeneratedVersion: ArticleVersion? {
        topic.currentVersion?.source == .generated ? topic.currentVersion : nil
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(topic.title).font(.headline)
                Text("\(topic.articleType.title) · \(topic.direction?.title ?? "—")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: runSelectedStage) {
                Label("Запустить этап", systemImage: "play.fill")
            }
            .disabled(executor?.isRunning ?? false)
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { onBack() } label: { Label("Контент-план", systemImage: "chevron.left") }
        }
        ToolbarItem { Button { showSemantics = true } label: { Label("Семантика", systemImage: "list.bullet") } }
        ToolbarItem { Button { showVersions = true } label: { Label("Версии", systemImage: "clock.arrow.circlepath") } }
        ToolbarItem { Button { showLog = true } label: { Label("Лог", systemImage: "doc.text") } }
    }

    private func runSelectedStage() {
        if selectedStage == .productBlocks { showProductBlocks = true; return }
        runStage(selectedStage, blocks: [])
    }

    private func runStage(_ stage: PipelineStage, blocks: [String]) {
        guard let executor else { return }
        comparisonText = topic.currentVersion?.text   // remember pre-generation text for the left column
        let template = fetchTemplate(for: stage)
        let current = topic.currentVersion?.text
        Task {
            await executor.execute(stage: stage, topic: topic, template: template,
                                   currentText: current, selectedBlocks: blocks, in: context)
        }
    }

    private func fetchTemplate(for stage: PipelineStage) -> StageTemplate {
        let raw = stage.rawValue
        let descriptor = FetchDescriptor<StageTemplate>(
            predicate: #Predicate { $0.stageRaw == raw }
        )
        if let found = (try? context.fetch(descriptor))?.first { return found }
        // Fallback: seed then refetch.
        StageTemplateSeeder.seedIfNeeded(in: context)
        return (try? context.fetch(descriptor))?.first
            ?? StageTemplate(stage: stage, systemPrompt: "", userPromptTemplate: "{{текущий_текст}}")
    }

    private func acceptAll() {
        // Generated version is already current; just clear the comparison view.
        comparisonText = nil
    }

    private func reject() {
        guard let pending = pendingGeneratedVersion else { return }
        pending.isArchived = true
        // Restore previous current version: the newest non-archived version before this one.
        let prior = topic.versions
            .filter { !$0.isArchived && $0.uuid != pending.uuid }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        topic.currentVersionID = prior?.uuid
        comparisonText = nil
    }

    private func applyPartial(base: String, generated: ArticleVersion, indices: Set<Int>) {
        let hybrid = VersionActions.assembleHybrid(old: base, new: generated.text, acceptedNewIndices: indices)
        generated.isArchived = true
        let version = ArticleVersion(stage: PipelineStage(rawValue: generated.stageRaw) ?? .draft,
                                     source: .acceptedPartial, text: hybrid)
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
        comparisonText = nil
    }
}
