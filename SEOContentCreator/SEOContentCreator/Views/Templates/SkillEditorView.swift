import SwiftData
import SwiftUI

struct SkillEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var skill: SkillPreset
    var onDelete: () -> Void

    @State private var name = ""
    @State private var prompt = ""
    @State private var roleKey = "editor"
    @State private var savedNote: String?

    private let roleOptions: [(key: String, name: String)] = [
        ("editor", "ИИ-редактор"),
        ("author", "ИИ-автор"),
        ("seo", "ИИ-SEO")
    ]

    private var defaultForSkill: SkillPresetDefault? {
        if let key = skill.defaultKey {
            return SkillPresetDefaults.all.first { $0.key == key }
        }
        return SkillPresetDefaults.all.first { $0.name == skill.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Скилл").font(.title2).bold()

                TextField("Название", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Picker("Роль", selection: $roleKey) {
                    ForEach(roleOptions, id: \.key) { Text($0.name).tag($0.key) }
                }
                .frame(maxWidth: 280, alignment: .leading)

                Text("Промт (что сделать с фрагментом)").font(.headline)
                TextEditor(text: $prompt).frame(minHeight: 180).border(.gray.opacity(0.3))

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    if defaultForSkill != nil {
                        Button("Сбросить к стандартному") { resetToDefault() }
                    }
                    Spacer()
                    Button("Удалить скилл", role: .destructive) { deleteSkill() }
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private func load() {
        name = skill.name
        prompt = skill.prompt
        roleKey = skill.roleKey
    }

    private func save() {
        skill.name = name
        skill.prompt = prompt
        skill.roleKey = roleKey
        skill.updatedAt = .now
        savedNote = "Сохранено"
    }

    private func resetToDefault() {
        guard let def = defaultForSkill else { return }
        prompt = def.prompt
        roleKey = def.roleKey
        save()
        savedNote = "Сброшено к стандартному"
    }

    private func deleteSkill() {
        context.delete(skill)
        onDelete()
    }
}
