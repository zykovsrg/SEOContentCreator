import SwiftUI
import SwiftData

struct TemplateSandboxSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @Query(sort: \Topic.updatedAt, order: .reverse) private var topics: [Topic]

    let stage: PipelineStage
    let template: StageTemplate

    @State private var selectedTopicID: PersistentIdentifier?
    @State private var executor: StageExecutor?

    private var selectedTopic: Topic? {
        if let selectedTopicID {
            return topics.first { $0.persistentModelID == selectedTopicID }
        }
        return topics.first
    }

    private var topicSelectionBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedTopicID ?? topics.first?.persistentModelID },
            set: { selectedTopicID = $0 }
        )
    }

    private var isRunning: Bool { executor?.isRunning ?? false }

    private var outputText: String {
        executor?.streamingText ?? ""
    }

    /// While generation runs, show only the tail (see `String.streamingTail`) to keep the UI
    /// responsive on long output; once it finishes, show the complete result.
    private var displayText: String {
        if outputText.isEmpty { return "Здесь появится ответ модели после запуска." }
        return isRunning ? outputText.streamingTail() : outputText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if topics.isEmpty {
                ContentUnavailableView(
                    "Нет тем для проверки",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Сначала создайте тему в контент-плане, затем вернитесь в песочницу.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker("Тема", selection: topicSelectionBinding) {
                    ForEach(topics) { topic in
                        Text(topic.title).tag(Optional(topic.persistentModelID))
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)

                topicPreview

                HStack(spacing: 8) {
                    Button("Запустить") { run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedTopic == nil || isRunning)

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let error = executor?.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let warning = executor?.lastWarningMessage {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                outputArea
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 560)
        .onAppear {
            if selectedTopicID == nil {
                selectedTopicID = topics.first?.persistentModelID
            }
        }
        .onChange(of: topics.map(\.persistentModelID)) { _, ids in
            guard let selectedTopicID else {
                self.selectedTopicID = ids.first
                return
            }
            if !ids.contains(selectedTopicID) {
                self.selectedTopicID = ids.first
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Песочница")
                    .font(.title2)
                    .bold()
                Text(stage.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Закрыть") { dismiss() }
        }
    }

    @ViewBuilder
    private var topicPreview: some View {
        if let topic = selectedTopic {
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.headline)
                Text("Тип: \(topic.articleType.title)")
                Text("Направление: \(topic.direction?.title ?? "—")")
                Text("Текущий текст: \(topic.currentVersion?.text.isEmpty == false ? "есть" : "нет")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var outputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Результат")
                .font(.headline)

            ScrollView {
                Text(displayText)
                    .foregroundStyle(outputText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 260)
            .border(.gray.opacity(0.3))
        }
    }

    private func run() {
        guard let topic = selectedTopic else { return }
        let exec = StageExecutor.live(model: model)
        executor = exec
        Task {
            await exec.executeSandbox(
                stage: stage,
                topic: topic,
                template: template,
                currentText: topic.currentVersion?.text,
                in: context
            )
        }
    }
}
