import SwiftUI
import SwiftData

struct TopicWorkspaceView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    var onBack: () -> Void

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @State private var selectedStage: PipelineStage = .structure
    @State private var executor: StageExecutor?
    @State private var comparisonText: String?     // left column override (lane compare)
    @State private var pendingVersionID: UUID?     // just-generated version awaiting accept
    @State private var acceptedRemarkIDs: Set<UUID> = []
    @State private var rejectedRemarkIDs: Set<UUID> = []
    @State private var highlightedQuote: String?
    @State private var showVersions = false
    @State private var showLog = false
    @State private var showProductBlocks = false
    @State private var showSemantics = false
    @State private var showStructure = false
    @State private var showHints = false
    @State private var showFragmentEdit = false
    @State private var showManualEdit = false
    @State private var showImages = false
    @State private var showPublish = false
    @State private var showPartialAccept = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            StageBarView(selectedStage: $selectedStage, topic: topic)
                .padding(.vertical, 8)
            Divider()
            if let error = executor?.lastErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                    Text(error).font(.callout)
                    Spacer()
                    Button("Скрыть") { executor?.lastErrorMessage = nil }
                }
                .padding(8)
                .background(Color.red.opacity(0.12))
                Divider()
            }
            if let warning = executor?.lastWarningMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(warning).font(.callout)
                    Spacer()
                    Button("Скрыть") { executor?.lastWarningMessage = nil }
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                Divider()
            }
            if isReviewing {
                HStack(spacing: 0) {
                    ScrollView {
                        HighlightedText(text: workingCopy, highlight: highlightedQuote)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    Divider()
                    RemarksPanelView(
                        remarks: executor?.remarks ?? [],
                        acceptedIDs: acceptedRemarkIDs,
                        rejectedIDs: rejectedRemarkIDs,
                        onAccept: { acceptedRemarkIDs.insert($0.id); rejectedRemarkIDs.remove($0.id) },
                        onReject: { rejectedRemarkIDs.insert($0.id); acceptedRemarkIDs.remove($0.id) },
                        onSelect: { highlightedQuote = $0.quote }
                    )
                    .frame(width: 380)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Отклонить всё", role: .destructive) { endReview() }
                    Button("Готово") { finishReview() }.keyboardShortcut(.defaultAction)
                }
                .padding(8)
            } else {
                SideBySideView(
                    leftText: comparisonText ?? topic.currentVersion?.text,
                    rightText: rightText,
                    isStreaming: executor?.isRunning ?? false
                )
                Divider()
                AcceptRejectBar(
                    canAct: pendingVersion != nil && !(executor?.isRunning ?? false),
                    onAcceptAll: acceptAll,
                    onAcceptPartial: { showPartialAccept = true },
                    onReject: reject
                )
            }
        }
        .navigationTitle(topic.title)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showVersions) {
            VersionLaneView(topic: topic) { comparisonText = $0.text }
        }
        .sheet(isPresented: $showLog) { JobLogView(topic: topic) }
        .sheet(isPresented: $showProductBlocks) {
            ProductBlocksSheet { runStage(.productBlocks, blocks: $0) }
        }
        .sheet(isPresented: $showSemantics) { SemanticsEditorSheet(topic: topic) }
        .sheet(isPresented: $showStructure) { StructureEditorSheet(topic: topic) }
        .sheet(isPresented: $showHints) { SoftHintsSheet(topic: topic) }
        .sheet(isPresented: $showFragmentEdit) { FragmentEditSheet(topic: topic) }
        .sheet(isPresented: $showManualEdit) { ManualEditSheet(topic: topic) }
        .sheet(isPresented: $showImages) { ImagesView(topic: topic) }
        .sheet(isPresented: $showPublish) {
            PublishSheet(topic: topic)
        }
        .sheet(isPresented: $showPartialAccept) {
            if let pending = pendingVersion {
                let base = topic.currentVersion?.text ?? ""
                PartialAcceptSheet(oldText: base, newText: pending.text) { acceptedIndices in
                    applyPartial(base: base, generated: pending, indices: acceptedIndices)
                }
            }
        }
        .onAppear { if executor == nil { executor = .live(model: model) } }
    }

    private var rightText: String? {
        if let executor, executor.isRunning { return executor.streamingText }
        return pendingVersion?.text
    }

    /// The just-generated version awaiting accept/reject (in the lane, not yet current).
    private var pendingVersion: ArticleVersion? {
        guard let id = pendingVersionID else { return nil }
        return topic.versions.first { $0.uuid == id && $0.status == .pending }
    }

    private var isReviewing: Bool {
        !(executor?.remarks.isEmpty ?? true)
    }

    private var reviewBaseText: String {
        topic.currentVersion?.text ?? ""
    }

    private var workingCopy: String {
        let accepted = (executor?.remarks ?? []).filter { acceptedRemarkIDs.contains($0.id) }
        return RemarkApplier.apply(base: reviewBaseText, accepted: accepted)
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
            Button(role: .destructive, action: { executor?.cancel() }) {
                Label("Стоп", systemImage: "stop.fill")
            }
            .disabled(!(executor?.isRunning ?? false))
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
        ToolbarItem { Button { showHints = true } label: { Label("Подсказки", systemImage: "text.magnifyingglass") } }
        ToolbarItem { Button { showFragmentEdit = true } label: { Label("Правка фрагмента", systemImage: "wand.and.stars") } }
        ToolbarItem {
            Button { showManualEdit = true } label: { Label("Ручная правка", systemImage: "pencil") }
                .disabled(topic.currentVersion == nil)
        }
        ToolbarItem { Button { showImages = true } label: { Label("Изображения", systemImage: "photo.on.rectangle") } }
        ToolbarItem {
            Button {
                showPublish = true
            } label: {
                Label("Опубликовать", systemImage: "paperplane")
            }
        }
    }

    private func runSelectedStage() {
        if selectedStage == .structure { showStructure = true; return }
        if selectedStage == .productBlocks { showProductBlocks = true; return }
        runStage(selectedStage, blocks: [])
    }

    private func runStage(_ stage: PipelineStage, blocks: [String]) {
        guard let executor else { return }
        comparisonText = nil
        acceptedRemarkIDs = []
        rejectedRemarkIDs = []
        highlightedQuote = nil
        if let message = StageRunGuard.messagePreventingRun(stage: stage, topic: topic) {
            executor.lastErrorMessage = message
            return
        }
        let template = fetchTemplate(for: stage)
        let current = topic.currentVersion?.text
        Task {
            await executor.execute(stage: stage, topic: topic, template: template,
                                   currentText: current, selectedBlocks: blocks,
                                   modelName: model, in: context)
            pendingVersionID = executor.lastResultVersionID
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
        guard let pending = pendingVersion else { return }
        pending.status = .accepted
        topic.currentVersionID = pending.uuid
        topic.updatedAt = .now
        pendingVersionID = nil
        comparisonText = nil
    }

    private func reject() {
        guard let pending = pendingVersion else { return }
        pending.status = .rejected
        pendingVersionID = nil
        comparisonText = nil
    }

    private func applyPartial(base: String, generated: ArticleVersion, indices: Set<Int>) {
        let hybrid = VersionActions.assembleHybrid(old: base, new: generated.text, acceptedNewIndices: indices)
        generated.status = .rejected
        let version = ArticleVersion(stage: PipelineStage(rawValue: generated.stageRaw) ?? .draft,
                                     source: .acceptedPartial, text: hybrid)
        version.status = .accepted
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
        pendingVersionID = nil
        comparisonText = nil
    }

    private func finishReview() {
        let base = reviewBaseText
        let accepted = (executor?.remarks ?? []).filter { acceptedRemarkIDs.contains($0.id) }
        let result = RemarkApplier.apply(base: base, accepted: accepted)
        if result != base {
            let version = ArticleVersion(stage: selectedStage, source: .checkApplied, text: result)
            version.status = .accepted
            version.topic = topic
            context.insert(version)
            topic.currentVersionID = version.uuid
            topic.updatedAt = .now
        }
        endReview()
    }

    private func endReview() {
        executor?.remarks = []
        acceptedRemarkIDs = []
        rejectedRemarkIDs = []
        highlightedQuote = nil
    }
}
