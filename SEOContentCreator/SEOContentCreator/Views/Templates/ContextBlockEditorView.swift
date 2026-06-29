import SwiftUI

struct ContextBlockEditorView: View {
    @Bindable var block: ContextBlock
    let roles: [AIRole]

    @State private var text = ""
    @State private var savedNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(block.title).font(.title2).bold()
                Text("Версия блока: \(block.version)")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Текст блока").font(.headline)
                TextEditor(text: $text)
                    .frame(minHeight: 260)
                    .border(.gray.opacity(0.3))

                Text("Используется ролями").font(.headline)
                Text(usedByRoles.isEmpty ? "Не используется" : usedByRoles.joined(separator: ", "))
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    Button("Сбросить к стандартному") { resetToDefault() }
                    Spacer()
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private var usedByRoles: [String] {
        roles
            .filter { $0.blockKeys.contains(block.key) }
            .map(\.name)
    }

    private func load() {
        text = block.text
    }

    private func save() {
        block.text = text
        block.version += 1
        block.updatedAt = .now
        savedNote = "Сохранено (версия \(block.version))"
    }

    private func resetToDefault() {
        guard let defaults = ContextBlockDefaults.defaultForKey(block.key) else { return }
        block.title = defaults.title
        text = defaults.text
        save()
        savedNote = "Сброшено к стандартному"
    }
}
