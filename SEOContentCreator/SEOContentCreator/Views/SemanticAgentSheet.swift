import SwiftData
import SwiftUI

struct SemanticAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    @Query(filter: #Predicate<PublishedSitePage> { $0.siteHost == "hadassah.moscow" })
    private var pages: [PublishedSitePage]

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @State private var candidates: [String] = []
    @State private var results: [SemanticAgentKeywordResult] = []
    @State private var isRunning = false
    @State private var message: String?

    private var includedResults: [SemanticAgentKeywordResult] {
        results.filter { $0.recommendation == .include }
    }

    private var excludedResults: [SemanticAgentKeywordResult] {
        results.filter { $0.recommendation == .exclude }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сбор семантики агентом").font(.headline)
            Text(topic.title).foregroundStyle(.secondary)

            if pages.isEmpty {
                Text("Индекс страниц сайта пустой. Проверка каннибализации будет неполной.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Сгенерировать тестовые запросы") { generateCandidates() }
                Button("Проанализировать через OpenAI") { analyze() }
                    .disabled(candidates.isEmpty || isRunning)
                Spacer()
                if isRunning { ProgressView() }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            HSplitView {
                candidateList
                resultList
            }

            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить в семантику") { saveResults() }
                    .disabled(results.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 900, height: 560)
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Кандидаты").font(.subheadline).bold()
            List(candidates, id: \.self) { query in
                Text(query)
            }
        }
        .frame(minWidth: 280)
    }

    private var resultList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                resultSection(title: "Рекомендуется включить", results: includedResults)
                resultSection(title: "Не рекомендуется включать", results: excludedResults)
            }
            .padding(.trailing, 8)
        }
        .frame(minWidth: 420)
    }

    private func resultSection(title: String, results: [SemanticAgentKeywordResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).bold()

            if results.isEmpty {
                Text("Пока нет результатов.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results, id: \.query) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.query).font(.headline)
                        Text(result.reasonCategory.label)
                        Text(result.explanation).foregroundStyle(.secondary)
                        if result.cannibalizationRisk != .none {
                            Text("Риск: \(result.cannibalizationRisk.label)")
                            Text(result.cannibalizationTitle ?? result.cannibalizationURL ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func generateCandidates() {
        candidates = SemanticMockKeywordCollector.collect(for: topic)
        results = []
        message = "Тестовые запросы готовы."
    }

    private func analyze() {
        isRunning = true
        message = nil
        Task {
            do {
                let analyzer = SemanticAgentAnalyzer.live(model: model)
                let analyzed = try await analyzer.analyze(topic: topic, queries: candidates.map { WordstatPhrase(text: $0, frequency: 0) })
                results = analyzed.keywords
                message = "Анализ завершён."
            } catch {
                message = error.localizedDescription
            }
            isRunning = false
        }
    }

    private func saveResults() {
        SemanticKeywordMerger.merge(results, into: topic)
        try? context.save()
        dismiss()
    }
}
