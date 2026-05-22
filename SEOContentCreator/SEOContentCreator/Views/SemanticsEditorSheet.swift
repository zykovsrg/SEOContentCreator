import SwiftUI
import SwiftData

struct SemanticsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @State private var bulkText = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Семантика (по одному запросу в строке)").font(.headline)
            TextEditor(text: $bulkText)
                .font(.body).frame(minHeight: 240).border(.gray.opacity(0.3))
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460, height: 380)
        .onAppear { bulkText = topic.semantics.joined(separator: "\n") }
    }

    private func save() {
        topic.semantics = bulkText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        topic.updatedAt = .now
        dismiss()
    }
}
