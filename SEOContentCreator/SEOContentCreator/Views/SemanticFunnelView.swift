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
                Button(isRunning ? "Собираю…" : "Собрать семантику") { collect() }
                    .disabled(isRunning)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
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
                Button("Закрыть") { dismiss() }
            }
        }
        .padding()
        .frame(width: 760, height: 620)
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

    private func collect() {
        isRunning = true
        message = nil

        Task {
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

                runID = try await runner.run(topic: topic, pages: pages, context: context)
                message = "Сбор завершён."
            } catch {
                if let runError = error as? SemanticCollectionRunner.RunError {
                    runID = runError.runID
                }
                message = error.localizedDescription
            }
            isRunning = false
        }
    }
}
