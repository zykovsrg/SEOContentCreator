import SwiftData
import SwiftUI

struct SemanticFunnelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic

    @Query(filter: #Predicate<PublishedSitePage> { $0.siteHost == "hadassah.moscow" })
    private var pages: [PublishedSitePage]
    @Query(sort: \SemanticStopWord.order) private var stopWords: [SemanticStopWord]
    @Query(sort: \SemanticQueryMask.order) private var masks: [SemanticQueryMask]

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @AppStorage("wordstatProviderKind") private var providerKindRaw = WordstatProviderKind.cloud.rawValue

    @State private var isRunning = false
    @State private var message: String?
    @State private var runID: UUID?
    @State private var progress: SemanticCollectionProgress = .planning
    @State private var startedAt: Date?
    @State private var collectionTask: Task<Void, Never>?
    @State private var stopRequested = false
    @State private var showResetConfirmation = false

    private var entries: [SemanticFunnelEntry] {
        guard let runID else { return [] }
        return topic.funnelEntries.filter { $0.runID == runID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сбор семантики").font(.headline)
            Text(topic.title).foregroundStyle(.secondary)

            if pages.isEmpty {
                Text("Индекс страниц сайта пустой. Проверка каннибализации будет неполной.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button(collectButtonLabel) { collect() }
                    .disabled(isRunning)
                    .keyboardShortcut(.defaultAction)
                if isRunning {
                    Button("Остановить", role: .destructive) { stopCollection() }
                } else if topic.collectionCheckpoint != nil {
                    Button("Сбросить") { showResetConfirmation = true }
                }
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
            }

            if !isRunning, let checkpoint = topic.collectionCheckpoint {
                Text("Прошлый сбор остановлен: \(checkpoint.completedSeeds.count) из \(checkpoint.seeds.count) запросов получено.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isRunning, let startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(progress.label).font(.callout).bold()
                        Text("Прошло \(elapsedText(from: startedAt, to: timeline.date)) · лимит 10:00")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SemanticFunnelLayer.allCases, id: \.self) { layer in
                        layerSection(layer)
                    }
                }
                .padding(.trailing, 8)
            }

            HStack {
                Spacer()
                Button("Закрыть") {
                    collectionTask?.cancel()
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 760, height: 620)
        .onDisappear {
            collectionTask?.cancel()
        }
        .confirmationDialog(
            "Сбросить сохранённый прогресс сбора?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) { resetProgress() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Весь прогресс текущего незавершённого сбора будет потерян.")
        }
    }

    @ViewBuilder
    private func layerSection(_ layer: SemanticFunnelLayer) -> some View {
        let rows = entries.filter { $0.layer == layer }

        if !rows.isEmpty {
            DisclosureGroup {
                ForEach(rows, id: \.uuid) { entry in
                    HStack(alignment: .top) {
                        Text(entry.text)
                        Spacer()
                        if let frequency = entry.frequency {
                            Text("\(frequency)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        if !entry.reason.isEmpty {
                            Text(entry.reason).foregroundStyle(.secondary).frame(width: 240, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                Text("\(layer.label) — \(rows.count)").font(.subheadline).bold()
            }
        }
    }

    private func makeWordstatProvider() -> WordstatProvider {
        switch WordstatProviderKind(rawValue: providerKindRaw) ?? .cloud {
        case .legacy:
            let token = (try? WordstatCredentialStore.loadLegacyToken()) ?? ""
            return WordstatLegacyClient(token: token).provider()
        case .cloud:
            let apiKey = (try? WordstatCredentialStore.loadCloudAPIKey()) ?? ""
            let folderID = (try? WordstatCredentialStore.loadCloudFolderID()) ?? ""
            return WordstatCloudClient(apiKey: apiKey, folderID: folderID).provider()
        }
    }

    private var collectButtonLabel: String {
        if isRunning { return "Собираю…" }
        return topic.collectionCheckpoint != nil ? "Продолжить сбор" : "Собрать семантику"
    }

    private func resetProgress() {
        do {
            try SemanticCollectionRunner.resetCheckpoint(for: topic, context: context)
        } catch {
            message = "Не удалось сбросить прогресс: \(error.localizedDescription)"
        }
    }

    private func collect() {
        isRunning = true
        message = nil
        progress = .planning
        startedAt = .now
        stopRequested = false

        collectionTask = Task {
            do {
                let planner = SemanticSeedPlanner.live(model: model)
                let analyzer = SemanticAgentAnalyzer.live(model: model)
                let checker = SemanticCannibalizationChecker.live(model: model)

                let runner = SemanticCollectionRunner(
                    planSeeds: { topic, masks in try await planner.plan(topic: topic, masks: masks) },
                    pullPhrases: makeWordstatProvider(),
                    analyzeRelevance: { topic, queries in try await analyzer.analyze(topic: topic, queries: queries) },
                    checkCannibalization: { keywords, pages in try await checker.check(keywords: keywords, pages: pages) },
                    stopWords: stopWords.filter(\.isEnabled).map(\.text),
                    masks: masks.filter(\.isEnabled).map(\.text),
                    threshold: 10,
                    limit: 100
                )

                var reportingRunner = runner
                reportingRunner.reportProgress = { progress = $0 }
                runID = try await SemanticCollectionDeadline.run(timeout: .seconds(600)) {
                    try await reportingRunner.run(topic: topic, pages: pages, context: context)
                }
                message = "Сбор завершён."
            } catch is CancellationError {
                message = stopRequested
                    ? "Сбор остановлен. Семантика темы не изменена."
                    : "Сбор отменён. Семантика темы не изменена."
            } catch {
                if let runError = error as? SemanticCollectionRunner.RunError {
                    runID = runError.runID
                }
                if topic.collectionCheckpoint != nil {
                    message = "\(error.localizedDescription)\nПрогресс сохранён, можно продолжить позже."
                } else {
                    message = error.localizedDescription
                }
            }
            isRunning = false
            startedAt = nil
            collectionTask = nil
        }
    }

    private func stopCollection() {
        stopRequested = true
        message = "Останавливаю сбор…"
        collectionTask?.cancel()
    }

    private func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
