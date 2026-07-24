import SwiftUI
import SwiftData

struct TopicWorkspaceView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    var onBack: () -> Void

    @Query private var stageTemplates: [StageTemplate]
    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @State private var selectedStage: PipelineStage = .structure
    @State private var executor: StageExecutor?
    @State private var comparisonText: String?     // left column override (lane compare)
    @State private var pendingVersionID: UUID?     // just-generated version awaiting accept
    @State private var acceptedRemarkIDs: Set<UUID> = []
    @State private var rejectedRemarkIDs: Set<UUID> = []
    @State private var redoingRemarkIDs: Set<UUID> = []
    /// Accepted remarks that produced nothing at all (degenerate quote, or a removal
    /// suggestion for text that isn't there) — flagged as «не применено».
    @State private var unresolvedRemarkIDs: Set<UUID> = []
    /// Accepted remarks whose quote wasn't found in the body, so their suggestion was
    /// appended in a trailing block instead of being lost — flagged as «добавлено в конец».
    @State private var appendedRemarkIDs: Set<UUID> = []
    /// Frozen text the current review's remarks were made against. Accepted remarks
    /// are re-applied from here on every toggle, so the current version can change
    /// under us without the edits drifting.
    @State private var reviewBaseSnapshot: String?
    /// The version that was current when the review started, to revert to on «Отклонить всё».
    @State private var reviewBaseVersionID: UUID?
    /// The single version that holds this review's applied edits, updated in place as
    /// remarks are accepted/rejected (so accepting N remarks does not create N versions).
    @State private var reviewAppliedVersionID: UUID?
    @State private var highlightedQuote: String?
    @State private var showInspector = true
    @State private var inspectorTab: InspectorTab = .remarks
    @State private var showProductBlocks = false
    @State private var showStructure = false
    @State private var showHints = false
    @State private var showEditor = false
    @State private var showImages = false
    @State private var showPublish = false
    @State private var showPartialAccept = false
    @State private var showPromptAnalysis = false
    @State private var checkedWithNoRemarks = false
    @State private var preparationPresentation = PreparationPresentationState()

    enum InspectorTab: String, CaseIterable, Identifiable {
        case remarks, versions, semantics, log
        var id: String { rawValue }
        var title: String {
            switch self {
            case .remarks:   return "Замечания"
            case .versions:  return "Версии"
            case .semantics: return "Семантика"
            case .log:       return "Лог"
            }
        }
    }

    var body: some View {
        Group {
            if showEditor {
                TopicEditorView(topic: topic) {
                    showEditor = false
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        StageRailView(
                            selectedStage: $selectedStage,
                            topic: topic,
                            openPreparation: { preparationPresentation.open($0) }
                        )
                            .panelCard()
                        workColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .panelCard()
                        if showInspector {
                            inspectorPanel
                                .frame(width: 360)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .panelCard()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .padding(.top, 10)
                    bottomBar
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground)
        .navigationTitle(topic.title)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showProductBlocks) {
            ProductBlocksSheet { runStage(.productBlocks, blocks: $0) }
        }
        .sheet(isPresented: $showStructure) { StructureEditorSheet(topic: topic) }
        .sheet(item: $preparationPresentation.destination) { destination in
            switch destination {
            case .readerIntent:
                ReaderIntentSheet(topic: topic)
            case .semantics:
                SemanticsWorkspaceSheet(topic: topic)
            }
        }
        .sheet(isPresented: $showHints) { SoftHintsSheet(topic: topic) }
        .sheet(isPresented: $showImages) { ImagesView(topic: topic) }
        .sheet(isPresented: $showPublish) {
            PublishSheet(topic: topic)
        }
        .sheet(isPresented: $showPromptAnalysis) {
            PromptRecommendationsSheet(topic: topic)
        }
        .sheet(isPresented: $showPartialAccept) {
            if let pending = pendingVersion {
                let base = topic.currentVersion?.text ?? ""
                PartialAcceptSheet(oldText: base, newText: pending.text) { acceptedIndices in
                    applyPartial(base: base, generated: pending, indices: acceptedIndices)
                }
            }
        }
        .onAppear {
            if executor == nil {
                executor = .live(model: model)
                restoreReviewIfNeeded()
            }
        }
    }

    /// Central working column: header, banners, then either the review view or
    /// the version view. The stage checklist lives to its left; the reference
    /// panels (versions / log / semantics / remarks) live in the inspector.
    private var workColumn: some View {
        VStack(spacing: 0) {
            header
            Divider()
            errorBanner
            warningBanner
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
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
    }

    @ViewBuilder
    private var warningBanner: some View {
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
    }

    /// The document/comparison/review body — no action bars (those live in
    /// `bottomBar` so the layout matches the mockup's fixed bottom action row).
    @ViewBuilder
    private var contentArea: some View {
        if isReviewing {
            ScrollViewReader { proxy in
                ScrollView {
                    HighlightedText(text: workingCopy, highlight: highlightedQuote)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .onChange(of: highlightedQuote) { _, _ in
                    guard let index = highlightedParagraphIndex else { return }
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
            }
        } else if isComparing {
            SideBySideView(
                leftText: comparisonText ?? leftText,
                rightText: rightText,
                isStreaming: executor?.isRunning ?? false
            )
        } else {
            SingleVersionView(
                title: "Текущая версия",
                text: comparisonText ?? leftText,
                banner: singleColumnBanner,
                showsTitle: false
            )
        }
    }

    /// Fixed bottom action row. Its content depends on state: reviewing remarks,
    /// a freshly generated version awaiting accept, or the normal run bar.
    @ViewBuilder
    private var bottomBar: some View {
        Group {
            if isReviewing {
                HStack {
                    Spacer()
                    Button("Отклонить всё", role: .destructive) { rejectAllReview() }
                    Button("Готово") { finishReview() }.keyboardShortcut(.defaultAction)
                }
            } else if pendingVersion != nil {
                AcceptRejectBar(
                    canAct: !(executor?.isRunning ?? false),
                    onAcceptAll: acceptAll,
                    onAcceptPartial: { showPartialAccept = true },
                    onReject: reject
                )
            } else {
                stageActionBar
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.panelSurface)
    }

    /// Normal run bar: what will run (stage + model) on the left, the primary
    /// "Запустить этап" (or "Стоп" while running) plus "Опубликовать" on the right.
    private var stageActionBar: some View {
        HStack(spacing: 10) {
            Text(stageRunSummary)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(0)
            Spacer(minLength: 8)
            Button("Опубликовать") { showPublish = true }
                .buttonStyle(.bordered)
                .frame(minWidth: 132)
                .fixedSize(horizontal: true, vertical: false)
            if executor?.isRunning ?? false {
                Button(role: .destructive, action: { executor?.cancel() }) {
                    Label("Стоп", systemImage: "stop.fill")
                }
                .frame(minWidth: 96)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button(action: runSelectedStage) {
                    Label("Запустить этап", systemImage: "play.fill")
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 168)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var stageRunSummary: String {
        let template = stageTemplates.first { $0.stageRaw == selectedStage.rawValue }
        let modelName = template?.modelName ?? model
        var summary = "Этап «\(selectedStage.title)» · \(modelName)"
        if let tokens = template?.maxTokens {
            summary += " · ~\(TemplateChipText.tokens(tokens))"
        }
        return summary
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            inspectorTabsBar
            Divider()
            switch inspectorTab {
            case .remarks:   remarksTab
            case .versions:  VersionLaneView(topic: topic) { comparisonText = $0.text }
            case .semantics: SemanticsEditorSheet(topic: topic)
            case .log:       JobLogView(topic: topic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Text tabs with a teal underline on the active one (matches the mockup,
    /// in place of a segmented control).
    private var inspectorTabsBar: some View {
        HStack(spacing: 18) {
            ForEach(InspectorTab.allCases) { tab in
                let active = inspectorTab == tab
                Button { inspectorTab = tab } label: {
                    Text(tab.title)
                        .font(.callout).fontWeight(active ? .semibold : .regular)
                        .foregroundStyle(active ? Color.primary : Color.secondary)
                        .padding(.bottom, 7)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(active ? Color.accentColor : Color.clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 10)
    }

    @ViewBuilder
    private var remarksTab: some View {
        if isReviewing {
            RemarksPanelView(
                remarks: executor?.remarks ?? [],
                acceptedIDs: acceptedRemarkIDs,
                rejectedIDs: rejectedRemarkIDs,
                unresolvedIDs: unresolvedRemarkIDs,
                appendedIDs: appendedRemarkIDs,
                redoingIDs: redoingRemarkIDs,
                onAccept: {
                    acceptedRemarkIDs.insert($0.id); rejectedRemarkIDs.remove($0.id)
                    RemarkPersistence.updateStatus(remarkID: $0.id, status: .accepted,
                                                   jobID: executor?.lastRemarksJobID, topic: topic)
                    applyAcceptedInstantly()
                },
                onReject: {
                    rejectedRemarkIDs.insert($0.id); acceptedRemarkIDs.remove($0.id)
                    RemarkPersistence.updateStatus(remarkID: $0.id, status: .rejected,
                                                   jobID: executor?.lastRemarksJobID, topic: topic)
                    applyAcceptedInstantly()
                },
                onSelect: { highlightedQuote = $0.quote },
                onRedo: { redoRemark($0, comment: $1) }
            )
        } else {
            ContentUnavailableView("Нет замечаний",
                                   systemImage: "checkmark.circle",
                                   description: Text("Запустите проверяющий этап (SEO, фактчекинг, вычитка), чтобы получить замечания."))
        }
    }

    private var rightText: String? {
        if let executor, executor.isRunning { return executor.streamingText }
        return pendingVersion?.text
    }

    /// The "Текущая версия" panel content. The "Структура" stage saves
    /// straight into `topic.structureText` (no `ArticleVersion`), so it
    /// needs its own source instead of `topic.currentVersion`.
    private var leftText: String? {
        if selectedStage == .structure {
            return topic.structureText.isEmpty ? nil : topic.structureText
        }
        return topic.currentVersion?.text
    }

    /// The just-generated version awaiting accept/reject (in the lane, not yet current).
    private var pendingVersion: ArticleVersion? {
        guard let id = pendingVersionID else { return nil }
        return topic.versions.first { $0.uuid == id && $0.status == .pending }
    }

    private var isReviewing: Bool {
        !(executor?.remarks.isEmpty ?? true)
    }

    private var isComparing: Bool {
        WorkspaceLayout.isComparing(
            stageKind: selectedStage.kind,
            isRunning: executor?.isRunning ?? false,
            hasPendingVersion: pendingVersion != nil
        )
    }

    private var singleColumnBanner: SingleVersionView.Banner? {
        if selectedStage.kind == .checking, executor?.isRunning ?? false { return .checking }
        if checkedWithNoRemarks { return .checkedNoRemarks }
        return nil
    }

    /// Frozen text the current review is applied against (falls back to the current
    /// version before a snapshot exists).
    private var reviewBase: String {
        reviewBaseSnapshot ?? topic.currentVersion?.text ?? ""
    }

    private var workingCopy: String {
        let accepted = (executor?.remarks ?? []).filter { acceptedRemarkIDs.contains($0.id) }
        return RemarkApplier.apply(base: reviewBase, accepted: accepted).text
    }

    private var highlightedParagraphIndex: Int? {
        guard let highlightedQuote, !highlightedQuote.isEmpty,
              let range = workingCopy.range(of: highlightedQuote)
        else { return nil }
        return TextParagraphs.index(of: range.lowerBound, in: TextParagraphs.ranges(in: workingCopy))
    }

    /// Top bar over the document: "Текущая версия" + version pill on the left,
    /// compare / editor actions on the right (matches the mockup).
    private var header: some View {
        HStack(spacing: 10) {
            Text("Текущая версия").font(.headline)
            if let version = topic.currentVersion {
                MetaChip(text: versionLabel(version))
            }
            Spacer()
            Button("Сравнить версии") {
                inspectorTab = .versions
                showInspector = true
            }
            .buttonStyle(.bordered)
            Button("Редактор") { showEditor = true }
                .disabled(topic.currentVersion == nil)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func versionLabel(_ version: ArticleVersion) -> String {
        let stage = PipelineStage(rawValue: version.stageRaw)?.title ?? version.stageRaw
        return "этап: \(stage)"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { onBack() } label: { Label("Контент-план", systemImage: "chevron.left") }
                .help("Контент-план")
        }
        ToolbarItem {
            Button { showHints = true } label: { Label("Подсказки", systemImage: "text.magnifyingglass") }
                .help("Подсказки")
        }
        ToolbarItem {
            Button { showEditor = true } label: { Label("Редактор", systemImage: "pencil") }
                .disabled(topic.currentVersion == nil)
                .help("Редактор")
        }
        ToolbarItem {
            Button { showImages = true } label: { Label("Изображения", systemImage: "photo.on.rectangle") }
                .disabled(!canGenerateImages)
                .help("Изображения")
        }
        ToolbarItem {
            Button {
                showPublish = true
            } label: {
                Label("Опубликовать", systemImage: "paperplane")
            }
            .help("Опубликовать")
        }
        ToolbarItem {
            Button { showPromptAnalysis = true } label: {
                Label("Рекомендации по промтам", systemImage: "lightbulb")
            }
            .help("Рекомендации по промтам")
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: {
                Label("Инспектор", systemImage: "sidebar.trailing")
            }
            .help("Показать/скрыть инспектор")
        }
    }

    private func runSelectedStage() {
        if selectedStage == .structure { showStructure = true; return }
        if selectedStage == .productBlocks { showProductBlocks = true; return }
        if selectedStage == .images {
            if let message = StageRunGuard.messagePreventingRun(stage: .images, topic: topic) {
                executor?.lastErrorMessage = message
                return
            }
            showImages = true
            return
        }
        runStage(selectedStage, blocks: [])
    }

    private var canGenerateImages: Bool {
        StageRunGuard.messagePreventingRun(stage: .images, topic: topic) == nil
    }

    private func runStage(_ stage: PipelineStage, blocks: [String]) {
        guard let executor else { return }
        comparisonText = nil
        acceptedRemarkIDs = []
        rejectedRemarkIDs = []
        unresolvedRemarkIDs = []
        appendedRemarkIDs = []
        reviewBaseSnapshot = nil
        reviewBaseVersionID = nil
        reviewAppliedVersionID = nil
        highlightedQuote = nil
        checkedWithNoRemarks = false
        if let message = StageRunGuard.messagePreventingRun(stage: stage, topic: topic) {
            executor.lastErrorMessage = message
            return
        }
        let template = fetchTemplate(for: stage)
        let current = topic.currentVersion?.text
        Task {
            await executor.execute(stage: stage, topic: topic, template: template,
                                   currentText: current, selectedBlocks: blocks,
                                   in: context)
            pendingVersionID = executor.lastResultVersionID
            if !executor.remarks.isEmpty {
                // Freeze the reviewed text so accepted remarks re-apply from a stable base.
                reviewBaseSnapshot = current ?? topic.currentVersion?.text ?? ""
                reviewBaseVersionID = topic.currentVersionID
                reviewAppliedVersionID = nil
                unresolvedRemarkIDs = []
                appendedRemarkIDs = []
                inspectorTab = .remarks
                showInspector = true
            }
            if stage.kind == .checking && executor.remarks.isEmpty && executor.lastErrorMessage == nil {
                checkedWithNoRemarks = true
                if stage == .finalReview { appendTechInfoIfNeeded() }
            }
            if stage == .promptAnalysis && executor.lastErrorMessage == nil {
                showPromptAnalysis = true
            }
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
            ?? StageTemplate(stage: stage, userPromptTemplate: "{{текущий_текст}}")
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

    /// Re-applies the currently accepted remarks to the frozen base and commits the
    /// result to the review's single version — called on every accept/reject so edits
    /// appear in the text immediately (per the user's chosen behaviour). A remark is
    /// never silently dropped: Title/H1/Description remarks go straight to those fields
    /// (`metadataEdits`), a body quote that can't be located is appended in a trailing
    /// block (`appendedIDs`), and only a truly degenerate remark is flagged «не применено».
    private func applyAcceptedInstantly() {
        let accepted = (executor?.remarks ?? []).filter { acceptedRemarkIDs.contains($0.id) }
        let result = RemarkApplier.apply(base: reviewBase, accepted: accepted)
        unresolvedRemarkIDs = result.unresolvedIDs
        appendedRemarkIDs = result.appendedIDs
        syncReviewVersion(text: result.text, metadataEdits: result.metadataEdits)
    }

    /// Writes `text` (and any Title/H1/Description edits) into the review's applied
    /// version, creating it lazily on the first real change and updating it in place
    /// afterwards (one version per review, not per accepted remark).
    private func syncReviewVersion(text: String, metadataEdits: [RemarkApplier.MetadataField: String] = [:]) {
        let base = topic.versions.first(where: { $0.uuid == reviewBaseVersionID })
        let h1 = metadataEdits[.h1] ?? base?.h1 ?? topic.currentVersion?.h1
        let seoTitle = metadataEdits[.seoTitle] ?? base?.seoTitle ?? topic.currentVersion?.seoTitle
        let seoDescription = metadataEdits[.seoDescription] ?? base?.seoDescription ?? topic.currentVersion?.seoDescription

        if let id = reviewAppliedVersionID,
           let version = topic.versions.first(where: { $0.uuid == id }) {
            version.text = text
            version.h1 = h1
            version.seoTitle = seoTitle
            version.seoDescription = seoDescription
            topic.currentVersionID = id
            topic.updatedAt = .now
            return
        }
        // Nothing applied yet: don't spawn a no-op version.
        guard text != reviewBase || !metadataEdits.isEmpty else { return }
        let version = ArticleVersion(stage: selectedStage, source: .checkApplied, text: text)
        version.status = .accepted
        version.h1 = h1
        version.seoTitle = seoTitle
        version.seoDescription = seoDescription
        version.topic = topic
        context.insert(version)
        reviewAppliedVersionID = version.uuid
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
    }

    private func finishReview() {
        let accepted = (executor?.remarks ?? []).filter { acceptedRemarkIDs.contains($0.id) }
        let result = RemarkApplier.apply(base: reviewBase, accepted: accepted)
        var text = result.text
        if selectedStage == .finalReview {
            text = TechInfoSectionBuilder.append(to: text, section: TechInfoSectionBuilder.section(for: topic))
        }
        syncReviewVersion(text: text, metadataEdits: result.metadataEdits)
        clearReviewState()
    }

    /// «Отклонить всё»: discard this review's edits and return to the pre-review text.
    private func rejectAllReview() {
        if let baseID = reviewBaseVersionID, topic.versions.contains(where: { $0.uuid == baseID }) {
            if let id = reviewAppliedVersionID,
               let version = topic.versions.first(where: { $0.uuid == id }) {
                context.delete(version)
            }
            topic.currentVersionID = baseID
            topic.updatedAt = .now
        } else if let id = reviewAppliedVersionID,
                  let version = topic.versions.first(where: { $0.uuid == id }) {
            // Base version unknown (e.g. review restored after restart): revert text in place.
            version.text = reviewBase
            topic.updatedAt = .now
        }
        clearReviewState()
    }

    /// «Финальная вычитка» прошла без замечаний: дописываем раздел
    /// «Техническая информация» отдельной принятой версией (если его ещё нет).
    private func appendTechInfoIfNeeded() {
        guard let current = topic.currentVersion else { return }
        let appended = TechInfoSectionBuilder.append(
            to: current.text, section: TechInfoSectionBuilder.section(for: topic))
        guard appended != current.text else { return }
        let version = ArticleVersion(stage: .finalReview, source: .checkApplied, text: appended)
        version.status = .accepted
        version.h1 = current.h1
        version.seoTitle = current.seoTitle
        version.seoDescription = current.seoDescription
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
    }

    private func redoRemark(_ remark: Remark, comment: String) {
        guard let executor else { return }
        redoingRemarkIDs.insert(remark.id)
        Task {
            defer { redoingRemarkIDs.remove(remark.id) }
            await RemarkRedoRunner.run(remark: remark, comment: comment, model: model,
                                       executor: executor, topic: topic, in: context)
            if let updated = executor.remarks.first(where: { $0.id == remark.id }) {
                RemarkPersistence.updateSuggestion(remarkID: remark.id, suggestion: updated.suggestion,
                                                   jobID: executor.lastRemarksJobID, topic: topic)
            }
            // If this remark was already accepted, re-apply so the refreshed suggestion lands.
            if acceptedRemarkIDs.contains(remark.id) { applyAcceptedInstantly() }
        }
    }

    private func restoreReviewIfNeeded() {
        guard let restored = RemarkPersistence.restoreLatestUnresolved(topic: topic) else { return }
        executor?.remarks = restored.remarks
        executor?.lastRemarksJobID = restored.jobID
        acceptedRemarkIDs = restored.accepted
        rejectedRemarkIDs = restored.rejected
        // Recover the frozen base so accepted remarks keep re-applying consistently.
        // The pre-review version id is not persisted, so «Отклонить всё» will revert
        // the applied text in place instead of pointing back to it.
        reviewBaseSnapshot = restored.baseText ?? topic.currentVersion?.text
        reviewBaseVersionID = nil
        reviewAppliedVersionID = nil
        let accepted = restored.remarks.filter { restored.accepted.contains($0.id) }
        let result = RemarkApplier.apply(base: reviewBaseSnapshot ?? "", accepted: accepted)
        unresolvedRemarkIDs = result.unresolvedIDs
        appendedRemarkIDs = result.appendedIDs
    }

    private func clearReviewState() {
        RemarkPersistence.resolve(jobID: executor?.lastRemarksJobID, topic: topic)
        executor?.remarks = []
        acceptedRemarkIDs = []
        rejectedRemarkIDs = []
        unresolvedRemarkIDs = []
        appendedRemarkIDs = []
        reviewBaseSnapshot = nil
        reviewBaseVersionID = nil
        reviewAppliedVersionID = nil
        highlightedQuote = nil
    }
}
