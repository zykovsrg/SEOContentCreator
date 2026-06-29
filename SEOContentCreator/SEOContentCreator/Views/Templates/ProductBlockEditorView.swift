import SwiftData
import SwiftUI

struct ProductBlockEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var block: ProductBlock
    var onDelete: () -> Void

    @State private var name = ""
    @State private var prompt = ""
    @State private var savedNote: String?

    private var defaultForBlock: ProductBlockDefault? {
        if let key = block.defaultKey {
            return ProductBlockDefaults.all.first { $0.key == key }
        }
        return ProductBlockDefaults.all.first { $0.name == block.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Продуктовый блок").font(.title2).bold()

                TextField("Название", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Text("Промт (что встроить в текст)").font(.headline)
                Text("Доступные переменные: {{преимущества}}, {{врач_данные}}, {{направление}}, {{тема}}")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $prompt).frame(minHeight: 180).border(.gray.opacity(0.3))

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    if defaultForBlock != nil {
                        Button("Сбросить к стандартному") { resetToDefault() }
                    }
                    Spacer()
                    Button("Удалить блок", role: .destructive) { deleteBlock() }
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private func load() {
        name = block.name
        prompt = block.prompt
    }

    private func save() {
        block.name = name
        block.prompt = prompt
        block.updatedAt = .now
        savedNote = "Сохранено"
    }

    private func resetToDefault() {
        guard let def = defaultForBlock else { return }
        prompt = def.prompt
        save()
        savedNote = "Сброшено к стандартному"
    }

    private func deleteBlock() {
        context.delete(block)
        onDelete()
    }
}
