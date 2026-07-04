import SwiftUI
import SwiftData

struct StructureEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    @AppStorage("openAIModel") private var model = "gpt-4.1"

    @State private var planText = ""
    @State private var executor: StageExecutor?

    private var isRunning: Bool { executor?.isRunning ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Структура статьи (план H1/H2/H3 с пометками)").font(.headline)
                Spacer()
                Button { generate() } label: {
                    Label(isRunning ? "Генерация…" : "Сгенерировать", systemImage: "sparkles")
                }
                .disabled(isRunning)
            }

            if let error = executor?.lastErrorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            if isRunning {
                // Show only the tail while streaming (see `String.streamingTail`); the full plan
                // appears in the editor below once generation finishes.
                ScrollView {
                    Text((executor?.streamingText ?? "").streamingTail())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(4)
                }
                .frame(minHeight: 320).border(.gray.opacity(0.3))
            } else {
                TextEditor(text: $planText)
                    .font(.body).frame(minHeight: 320).border(.gray.opacity(0.3))
            }

            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning)
            }
        }
        .padding()
        .frame(width: 640, height: 560)
        .onAppear {
            planText = topic.structureText
            if executor == nil { executor = .live(model: model) }
        }
    }

    private func generate() {
        guard let executor else { return }
        let template = fetchStructureTemplate()
        Task {
            await executor.execute(stage: .structure, topic: topic, template: template,
                                   currentText: nil, modelName: model, in: context)
            if executor.lastErrorMessage == nil {
                planText = executor.streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func save() {
        topic.structureText = planText
        topic.updatedAt = .now
        dismiss()
    }

    private func fetchStructureTemplate() -> StageTemplate {
        let raw = PipelineStage.structure.rawValue
        let descriptor = FetchDescriptor<StageTemplate>(predicate: #Predicate { $0.stageRaw == raw })
        if let found = (try? context.fetch(descriptor))?.first { return found }
        StageTemplateSeeder.seedIfNeeded(in: context)
        let c = StageTemplateDefaults.content(for: .structure)
        return (try? context.fetch(descriptor))?.first
            ?? StageTemplate(stage: .structure, userPromptTemplate: c.userPromptTemplate)
    }
}
