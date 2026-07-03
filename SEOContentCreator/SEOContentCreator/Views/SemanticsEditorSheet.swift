import SwiftData
import SwiftUI

struct SemanticsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    @Query(filter: #Predicate<PublishedSitePage> { $0.siteHost == "hadassah.moscow" })
    private var indexedPages: [PublishedSitePage]

    @State private var filter: SemanticFilter = .all
    @State private var selectedIDs: Set<UUID> = []
    @State private var showAgent = false
    @State private var isRefreshingPages = false
    @State private var message: String?
    @State private var newKeywordText: String = ""
    @State private var showBulkAdd = false
    @State private var bulkKeywordText: String = ""

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

            HStack {
                TextField("Добавить запрос вручную", text: $newKeywordText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addManualKeyword() }
                Button("Добавить") { addManualKeyword() }
                    .disabled(newKeywordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Вставить список...") {
                    bulkKeywordText = ""
                    showBulkAdd = true
                }
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
        .sheet(isPresented: $showBulkAdd) {
            bulkAddSheet
        }
    }

    private var bulkAddSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Вставить список запросов").font(.headline)
            Text("Один запрос на строку. Можно вставить из Wordstat — частотность через таб "
                + "распознаётся автоматически.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $bulkKeywordText)
                .font(.body.monospaced())
                .frame(minWidth: 460, minHeight: 320)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack {
                Spacer()
                Button("Отмена") { showBulkAdd = false }
                Button("Добавить всё") {
                    addBulkKeywords()
                    showBulkAdd = false
                }
                .disabled(bulkKeywordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 520)
    }

    private func addManualKeyword() {
        let text = newKeywordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if topic.semanticKeywords.contains(where: { $0.text.localizedCaseInsensitiveCompare(text) == .orderedSame }) {
            message = "Такой запрос уже есть в списке."
            return
        }
        let keyword = SemanticKeyword(text: text, userDecision: .accepted)
        keyword.topic = topic
        topic.semanticKeywords.append(keyword)
        context.insert(keyword)
        topic.updatedAt = .now
        newKeywordText = ""
        message = nil
    }

    private func addBulkKeywords() {
        var existingTexts = Set(topic.semanticKeywords.map { $0.text.localizedLowercase })
        var added = 0
        var skipped = 0

        for rawLine in bulkKeywordText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let (text, frequency) = parseWordstatLine(line)
            guard !text.isEmpty else { continue }

            let key = text.localizedLowercase
            guard !existingTexts.contains(key) else {
                skipped += 1
                continue
            }

            let keyword = SemanticKeyword(text: text, frequency: frequency, userDecision: .accepted)
            keyword.topic = topic
            topic.semanticKeywords.append(keyword)
            context.insert(keyword)
            existingTexts.insert(key)
            added += 1
        }

        if added > 0 {
            topic.updatedAt = .now
        }
        message = "Добавлено запросов: \(added)" + (skipped > 0 ? ", пропущено дубликатов: \(skipped)." : ".")
        bulkKeywordText = ""
    }

    /// Wordstat при копировании строки таблицы обычно даёт "запрос<TAB>частотность".
    private func parseWordstatLine(_ line: String) -> (text: String, frequency: Int?) {
        let parts = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count > 1, let lastPart = parts.last else {
            return (line, nil)
        }
        let digitsOnly = lastPart.filter { $0.isNumber }
        if !digitsOnly.isEmpty, let frequency = Int(digitsOnly) {
            let text = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return (text.isEmpty ? lastPart : text, frequency)
        }
        return (parts.joined(separator: " ").trimmingCharacters(in: .whitespaces), nil)
    }

    private func setDecision(_ decision: SemanticUserDecision) {
        for keyword in topic.semanticKeywords where selectedIDs.contains(keyword.uuid) {
            keyword.userDecision = decision
        }
        topic.updatedAt = .now
    }

    private func refreshSitePages() {
        isRefreshingPages = true
        message = "Обновляю страницы сайта..."
        Task {
            do {
                let freshPages = try await SitePageIndexer().fetchPages()
                for page in indexedPages {
                    context.delete(page)
                }
                for page in freshPages {
                    context.insert(page)
                }
                try? context.save()
                message = "Индекс сайта обновлён: \(freshPages.count) страниц."
            } catch {
                message = "Не удалось обновить страницы сайта. Можно продолжить со старым индексом."
            }
            isRefreshingPages = false
        }
    }
}
