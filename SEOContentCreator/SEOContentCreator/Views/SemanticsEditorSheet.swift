import SwiftData
import SwiftUI

struct SemanticsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @State private var filter: SemanticFilter = .all
    @State private var selectedIDs: Set<UUID> = []
    @State private var showAgent = false
    @State private var isRefreshingPages = false
    @State private var message: String?

    private enum SemanticFilter: String, CaseIterable, Identifiable {
        case all
        case pending
        case accepted
        case rejected
        case include
        case exclude

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "Все"
            case .pending: return "Ожидают"
            case .accepted: return "Принятые"
            case .rejected: return "Отклонённые"
            case .include: return "Рекомендуется"
            case .exclude: return "Не рекомендуется"
            }
        }
    }

    private var visibleKeywords: [SemanticKeyword] {
        topic.semanticKeywords.filter { keyword in
            switch filter {
            case .all: return true
            case .pending: return keyword.userDecision == .pending
            case .accepted: return keyword.userDecision == .accepted
            case .rejected: return keyword.userDecision == .rejected
            case .include: return keyword.agentRecommendation == .include
            case .exclude: return keyword.agentRecommendation == .exclude
            }
        }.sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Семантика").font(.headline)
                Spacer()
                Picker("Фильтр", selection: $filter) {
                    ForEach(SemanticFilter.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.menu)
                Button("Обновить страницы сайта") { refreshSitePages() }
                    .disabled(isRefreshingPages)
                Button("Сбор агентом") { showAgent = true }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            Table(visibleKeywords, selection: $selectedIDs) {
                TableColumn("Запрос") { Text($0.text) }
                TableColumn("Частотность") { Text($0.frequency.map(String.init) ?? "-") }
                TableColumn("Рекомендация") { Text($0.agentRecommendation.label) }
                TableColumn("Решение") { Text($0.userDecision.label) }
                TableColumn("Причина") { Text($0.reasonCategory.label) }
                TableColumn("Риск") { Text($0.cannibalizationRisk.label) }
                TableColumn("Страница") { keyword in
                    Text(keyword.cannibalizationTitle ?? keyword.cannibalizationURL ?? "-")
                        .lineLimit(1)
                }
            }

            HStack {
                Button("Принять выбранные") { setDecision(.accepted) }
                    .disabled(selectedIDs.isEmpty)
                Button("Отклонить выбранные") { setDecision(.rejected) }
                    .disabled(selectedIDs.isEmpty)
                Button("Сделать обязательными") { setDecision(.required) }
                    .disabled(selectedIDs.isEmpty)
                Spacer()
                Button("Закрыть") { dismiss() }
            }
        }
        .padding()
        .frame(width: 980, height: 560)
        .onAppear {
            SemanticKeywordBackfill.backfill(topic)
        }
        .sheet(isPresented: $showAgent) {
            SemanticAgentSheet(topic: topic)
        }
    }

    private func setDecision(_ decision: SemanticUserDecision) {
        for keyword in topic.semanticKeywords where selectedIDs.contains(keyword.uuid) {
            keyword.userDecision = decision
        }
        topic.updatedAt = .now
    }

    private func refreshSitePages() {
        message = "Обновление индекса сайта будет подключено в следующем шаге."
    }
}
