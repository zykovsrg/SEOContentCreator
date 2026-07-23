import SwiftData
import SwiftUI

/// Minus-words and question masks for the semantic collection funnel.
struct SemanticReferenceEditorView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SemanticStopWord.order) private var stopWords: [SemanticStopWord]
    @Query(sort: \SemanticQueryMask.order) private var masks: [SemanticQueryMask]

    @State private var newStopWord = ""
    @State private var newMask = ""

    var body: some View {
        HSplitView {
            stopWordColumn
            maskColumn
        }
        .padding()
    }

    private var stopWordColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Минус-слова").font(.headline)
            Text("Запрос с таким словом не попадёт в семантику ни по одной теме.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                TextField("Новое слово", text: $newStopWord)
                    .onSubmit { addStopWord() }
                Button("Добавить") { addStopWord() }
                    .disabled(newStopWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(stopWords, id: \.uuid) { word in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { word.isEnabled },
                            set: { word.isEnabled = $0; word.updatedAt = .now }
                        ))
                        .labelsHidden()
                        Text(word.text)
                        Spacer()
                        Button(role: .destructive) {
                            context.delete(word)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .frame(minWidth: 300)
    }

    private var maskColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Вопросительные маски").font(.headline)
            Text("Из этого списка агент выбирает слова для сбора информационных запросов.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                TextField("Новая маска", text: $newMask)
                    .onSubmit { addMask() }
                Button("Добавить") { addMask() }
                    .disabled(newMask.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(masks, id: \.uuid) { mask in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { mask.isEnabled },
                            set: { mask.isEnabled = $0; mask.updatedAt = .now }
                        ))
                        .labelsHidden()
                        Text(mask.text)
                        Spacer()
                        Button(role: .destructive) {
                            context.delete(mask)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .frame(minWidth: 300)
    }

    private func addStopWord() {
        let text = newStopWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        context.insert(SemanticStopWord(text: text, order: (stopWords.map(\.order).max() ?? -1) + 1))
        newStopWord = ""
    }

    private func addMask() {
        let text = newMask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        context.insert(SemanticQueryMask(text: text, order: (masks.map(\.order).max() ?? -1) + 1))
        newMask = ""
    }
}
