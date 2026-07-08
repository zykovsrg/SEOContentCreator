import SwiftUI
import SwiftData

struct QuickCheckSheet: View {
    let showsCloseButton: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("openAIModel") private var model = "gpt-4.1"

    // Только проверки (kind == .checking).
    private let checkStages: [PipelineStage] = [.seoCheck, .factCheck, .finalReview]

    @State private var inputText = ""
    @State private var selectedStage: PipelineStage = .seoCheck
    @State private var executor: StageExecutor?
    @State private var acceptedRemarkIDs: Set<UUID> = []
    @State private var rejectedRemarkIDs: Set<UUID> = []
    @State private var redoingRemarkIDs: Set<UUID> = []
    @State private var didRun = false
    @State private var highlightedQuote: String?

    // Сохранение как тему.
    @State private var showingSaveDialog = false
    @State private var newTopicTitle = ""
    @State private var copiedNote = false

    private var remarks: [Remark] { executor?.remarks ?? [] }
    private var isRunning: Bool { executor?.isRunning ?? false }

    private var correctedText: String {
        let accepted = remarks.filter { acceptedRemarkIDs.contains($0.id) }
        return RemarkApplier.apply(base: inputText, accepted: accepted)
    }

    init(showsCloseButton: Bool = true) {
        self.showsCloseButton = showsCloseButton
    }

    private var highlightedParagraphIndex: Int? {
        guard let highlightedQuote, !highlightedQuote.isEmpty,
              let range = inputText.range(of: highlightedQuote)
        else { return nil }
        return TextParagraphs.index(of: range.lowerBound, in: TextParagraphs.ranges(in: inputText))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Быстрая проверка").font(.title2).bold()
                Spacer()
                if showsCloseButton {
                    Button("Закрыть") { dismiss() }
                }
            }

            Picker("Проверка", selection: $selectedStage) {
                ForEach(checkStages) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("Вставьте текст для проверки").font(.headline)
            if didRun && !isRunning {
                ScrollViewReader { proxy in
                    ScrollView {
                        HighlightedText(text: inputText, highlight: highlightedQuote)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }
                    .frame(minHeight: 140).border(.gray.opacity(0.3))
                    .onChange(of: highlightedQuote) { _, _ in
                        guard let index = highlightedParagraphIndex else { return }
                        withAnimation { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            } else {
                TextEditor(text: $inputText).frame(minHeight: 140).border(.gray.opacity(0.3))
            }

            HStack {
                Button("Проверить") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                if isRunning { ProgressView().controlSize(.small) }
                if let msg = executor?.lastErrorMessage {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }

            if let warning = executor?.lastWarningMessage {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }

            if didRun && !isRunning {
                Divider()
                RemarksPanelView(
                    remarks: remarks,
                    acceptedIDs: acceptedRemarkIDs,
                    rejectedIDs: rejectedRemarkIDs,
                    redoingIDs: redoingRemarkIDs,
                    onAccept: { acceptedRemarkIDs.insert($0.id); rejectedRemarkIDs.remove($0.id) },
                    onReject: { rejectedRemarkIDs.insert($0.id); acceptedRemarkIDs.remove($0.id) },
                    onSelect: { highlightedQuote = $0.quote },
                    onRedo: { redoRemark($0, comment: $1) }
                )
                .frame(minHeight: 160)

                HStack {
                    Button("Скопировать результат") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(correctedText, forType: .string)
                        copiedNote = true
                    }
                    Button("Сохранить как тему") {
                        newTopicTitle = QuickCheckTitle.suggest(from: correctedText)
                        showingSaveDialog = true
                    }
                    Spacer()
                    if copiedNote { Text("Скопировано").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 560)
        .alert("Сохранить как тему", isPresented: $showingSaveDialog) {
            TextField("Название темы", text: $newTopicTitle)
            Button("Сохранить") { saveAsTopic() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Будет создана новая тема с исправленным текстом.")
        }
    }

    private func redoRemark(_ remark: Remark, comment: String) {
        guard let executor else { return }
        redoingRemarkIDs.insert(remark.id)
        Task {
            defer { redoingRemarkIDs.remove(remark.id) }
            await RemarkRedoRunner.run(remark: remark, comment: comment, model: model,
                                       executor: executor, topic: nil, in: context)
        }
    }

    private func run() {
        copiedNote = false
        acceptedRemarkIDs = []
        rejectedRemarkIDs = []
        highlightedQuote = nil
        didRun = false
        let template = fetchTemplate(for: selectedStage)
        let exec = StageExecutor.live(model: model)
        executor = exec
        Task {
            await exec.executeQuickCheck(
                stage: selectedStage,
                pastedText: inputText,
                template: template,
                modelName: model,
                in: context
            )
            // Show the remarks panel only on a successful run; on error the red
            // message in the run row is shown instead of an empty panel.
            didRun = exec.lastErrorMessage == nil
        }
    }

    private func saveAsTopic() {
        let title = newTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = Topic(title: title.isEmpty ? "Быстрая проверка" : title, articleType: .info)
        context.insert(topic)
        let version = ArticleVersion(stage: selectedStage, source: .checkApplied, text: correctedText)
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        dismiss()
    }

    private func fetchTemplate(for stage: PipelineStage) -> StageTemplate {
        let raw = stage.rawValue
        let descriptor = FetchDescriptor<StageTemplate>(predicate: #Predicate { $0.stageRaw == raw })
        if let found = (try? context.fetch(descriptor))?.first { return found }
        StageTemplateSeeder.seedIfNeeded(in: context)
        return (try? context.fetch(descriptor))?.first
            ?? StageTemplate(stage: stage, userPromptTemplate: "{{текущий_текст}}")
    }
}
