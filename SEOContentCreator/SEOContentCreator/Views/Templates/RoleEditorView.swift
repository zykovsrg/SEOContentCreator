import SwiftUI

struct RoleEditorView: View {
    @Bindable var role: AIRole
    let blocks: [ContextBlock]

    @State private var name = ""
    @State private var mandate = ""
    @State private var selectedBlockKeys: Set<String> = []
    @State private var savedNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(role.name).font(.title2).bold()
                Text("Версия роли: \(role.version)")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("Имя", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Text("Установка роли").font(.headline)
                TextEditor(text: $mandate)
                    .frame(minHeight: 180)
                    .border(.gray.opacity(0.3))

                Text("Использует блоки").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(blocks) { block in
                        Toggle(block.title, isOn: binding(for: block.key))
                    }
                }

                Text("Отвечает за этапы").font(.headline)
                Text(stageTitles.isEmpty ? "Нет закреплённых этапов" : stageTitles.joined(separator: ", "))
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

    private var stageTitles: [String] {
        PipelineStage.allCases
            .filter { $0.roleKey == role.key }
            .map(\.title)
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedBlockKeys.contains(key) },
            set: { isOn in
                if isOn {
                    selectedBlockKeys.insert(key)
                } else {
                    selectedBlockKeys.remove(key)
                }
            }
        )
    }

    private func load() {
        name = role.name
        mandate = role.mandate
        selectedBlockKeys = Set(role.blockKeys)
    }

    private func save() {
        role.name = name
        role.mandate = mandate
        role.blockKeys = orderedSelectedBlockKeys()
        role.version += 1
        role.updatedAt = .now
        savedNote = "Сохранено (версия \(role.version))"
    }

    private func resetToDefault() {
        guard let defaults = RoleDefaults.defaultForKey(role.key) else { return }
        name = defaults.name
        mandate = defaults.mandate
        selectedBlockKeys = Set(defaults.blockKeys)
        save()
        savedNote = "Сброшено к стандартному"
    }

    private func orderedSelectedBlockKeys() -> [String] {
        let canonical = ContextBlockDefaults.canonicalOrder.filter { selectedBlockKeys.contains($0) }
        let extra = blocks
            .map(\.key)
            .filter { selectedBlockKeys.contains($0) && !canonical.contains($0) }
        return canonical + extra
    }
}
