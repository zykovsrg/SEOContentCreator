import SwiftUI
import SwiftData

struct ManualEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ручная правка текста").font(.headline)
            Text("Правка сохранится как новая версия и станет текущей.")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $text)
                .frame(minHeight: 420)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
        }
        .padding()
        .frame(width: 720, height: 560)
        .onAppear { text = topic.currentVersion?.text ?? "" }
    }

    private var hasChanges: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && text != (topic.currentVersion?.text ?? "")
    }

    private func save() {
        VersionActions.applyManualEdit(topic: topic, newText: text, in: context)
        dismiss()
    }
}
