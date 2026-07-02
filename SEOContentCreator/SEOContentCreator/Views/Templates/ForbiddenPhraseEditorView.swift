import SwiftData
import SwiftUI

struct ForbiddenPhraseEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var phrase: ForbiddenPhrase
    var onDelete: () -> Void

    @State private var phraseText = ""
    @State private var problemText = ""
    @State private var replacementText = ""
    @State private var savedNote: String?
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Запрещённая формулировка").font(.title2).bold()

                Text("Формулировка").font(.headline)
                Text("Как написано сейчас и как больше не стоит писать.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $phraseText)
                    .frame(minHeight: 72)
                    .border(.gray.opacity(0.3))

                Text("В чём проблема").font(.headline)
                TextEditor(text: $problemText)
                    .frame(minHeight: 72)
                    .border(.gray.opacity(0.3))

                Text("Как можно заменить").font(.headline)
                TextEditor(text: $replacementText)
                    .frame(minHeight: 72)
                    .border(.gray.opacity(0.3))

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Удалить формулировку", role: .destructive) { confirmingDelete = true }
                    if let savedNote {
                        Text(savedNote).font(.caption).foregroundStyle(.green)
                    }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
        .confirmationDialog(
            "Удалить формулировку «\(phrase.phrase)»?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { deletePhrase() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func load() {
        phraseText = phrase.phrase
        problemText = phrase.problem
        replacementText = phrase.replacement
    }

    private func save() {
        phrase.phrase = phraseText.trimmingCharacters(in: .whitespacesAndNewlines)
        phrase.problem = problemText.trimmingCharacters(in: .whitespacesAndNewlines)
        phrase.replacement = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        phrase.updatedAt = .now
        savedNote = "Сохранено"
    }

    private func deletePhrase() {
        context.delete(phrase)
        onDelete()
    }
}
