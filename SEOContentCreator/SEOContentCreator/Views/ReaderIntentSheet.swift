import SwiftData
import SwiftUI

struct ReaderIntentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @State private var draft = ReaderIntentDraft(intent: nil)
    @State private var draftSource: ReaderIntentSource = .manual
    @State private var isRunning = false
    @State private var errorMessage: String?

    private var hasSemanticEvidence: Bool {
        !ReaderIntent.acceptedSemanticSnapshot(for: topic).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Задача читателя").font(.title2.bold())
                        Text("Карта помогает структуре и тексту отвечать на практический поисковый интент.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: generate) {
                        Label(
                            topic.readerIntent == nil ? "Сформировать с ИИ" : "Обновить с ИИ",
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(isRunning)
                }

                if !hasSemanticEvidence {
                    Label(
                        "Принятых или обязательных запросов пока нет. ИИ сможет сделать черновик, но уверенность будет ниже.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }

                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("ИИ формирует черновик. Текущие поля остаются доступными для просмотра.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                        .font(.callout).foregroundStyle(.red)
                }

                GroupBox("Основная задача") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Поисковый запрос", text: $draft.query)
                        field("Кто читатель и в какой ситуации", text: $draft.audienceContext, height: 64)
                        field("Практическая задача", text: $draft.hiddenGoal, height: 72)
                        field("Ответ полезен, если…", text: $draft.successCriterion, height: 64)
                        field("Барьеры и сомнения", text: $draft.barriers, height: 72)
                    }
                    .padding(.top, 6)
                }

                GroupBox("Форма решения") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Тип решения", selection: $draft.solutionType) {
                            ForEach(ReaderIntentSolutionType.allCases) { value in
                                Text(solutionTitle(value)).tag(value)
                            }
                        }
                        TextField("Формат: сравнение, алгоритм, объяснение…", text: $draft.solutionFormat)
                    }
                    .padding(.top, 6)
                }

                GroupBox("Необходимое покрытие") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                        ForEach(ReaderIntentCoverage.allCases) { value in
                            Toggle(coverageTitle(value), isOn: coverageBinding(value))
                                .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("Формула задачи") {
                    Text(draft.taskFormula)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || !draft.canSave)
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .frame(width: 760, height: 720)
        .onAppear(perform: load)
    }

    private func field(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: height)
                .padding(5)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func coverageBinding(_ value: ReaderIntentCoverage) -> Binding<Bool> {
        Binding(
            get: { draft.coverage.contains(value) },
            set: { enabled in
                if enabled { draft.coverage.insert(value) } else { draft.coverage.remove(value) }
            }
        )
    }

    private func load() {
        draft = ReaderIntentDraft(intent: topic.readerIntent)
        draftSource = topic.readerIntent?.source ?? .manual
    }

    private func generate() {
        isRunning = true
        errorMessage = nil
        Task {
            defer { isRunning = false }
            do {
                draft = try await ReaderIntentAnalyzer.live(model: model).analyze(topic: topic)
                draftSource = .ai
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        errorMessage = nil
        do {
            draft.apply(to: topic, source: draftSource, in: context)
            try context.save()
            dismiss()
        } catch {
            errorMessage = "Не удалось сохранить карту: \(error.localizedDescription)"
        }
    }

    private func solutionTitle(_ value: ReaderIntentSolutionType) -> String {
        switch value {
        case .explanation: return "Объяснение"
        case .algorithm: return "Алгоритм"
        case .comparison: return "Сравнение"
        case .directOffer: return "Прямое предложение"
        case .mixed: return "Смешанный"
        }
    }

    private func coverageTitle(_ value: ReaderIntentCoverage) -> String {
        switch value {
        case .definition: return "Определение"
        case .currentRelevance: return "Актуальность сейчас"
        case .choiceComparison: return "Выбор и сравнение"
        case .evidence: return "Доказательства"
        case .socialProof: return "Социальное подтверждение"
        case .applicationContext: return "Контекст применения"
        case .risksLimitations: return "Риски и ограничения"
        case .practicalSolution: return "Практическое решение"
        }
    }
}
