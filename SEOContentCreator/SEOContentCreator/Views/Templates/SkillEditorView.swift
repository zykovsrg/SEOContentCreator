import Foundation
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
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var insertionToken = ""
    @State private var insertionRequestID = 0

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
        HStack(spacing: 10) {
            editorPanel
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                .panelCard()
            sidePanel
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .panelCard()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground)
        .navigationTitle(name.isEmpty ? skill.name : name)
        .onAppear(perform: load)
    }

    private var editorPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PromptTemplateTextEditor(
                text: $prompt,
                selectedRange: $selectedRange,
                insertionToken: insertionToken,
                insertionRequestID: insertionRequestID
            )
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(18)
            Divider()
            bottomBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Шаблоны › Скиллы › \(name.isEmpty ? skill.name : name)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Text("Скилл")
                    .font(.title)
                    .fontWeight(.bold)
                Text(roleName(for: roleKey))
                    .font(.callout).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            TextField("Название", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 460)

            Text("Промт описывает, что скилл делает с выделенным фрагментом текста.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                roleSection
                Divider()
                helpSection
                if defaultForSkill != nil {
                    Divider()
                    defaultsSection
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorPanelTitle("Параметры скилла")
            Picker("Роль", selection: $roleKey) {
                ForEach(roleOptions, id: \.key) { option in
                    Text(option.name).tag(option.key)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Text("Эта роль будет выполнять скилл в редакторе темы.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorPanelTitle("Как используется")
            VStack(alignment: .leading, spacing: 6) {
                Text("Скилл применяется к выделенному фрагменту.")
                    .font(.callout)
                Text("Пиши короткую инструкцию без переменных: приложение само передаст выбранный текст.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorPanelTitle("Стандартный шаблон")
            Text(defaultForSkill?.name ?? "")
                .font(.callout.weight(.semibold))
            Text("Сброс вернёт название роли и промт из заводского набора.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if defaultForSkill != nil {
                Button("Сбросить к стандартному") { resetToDefault() }
                    .foregroundStyle(.secondary)
            }
            Button("Удалить скилл", role: .destructive) { deleteSkill() }
            Spacer()
            if let savedNote {
                Text(savedNote)
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            Button("Сохранить") { save() }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    private func roleName(for key: String) -> String {
        roleOptions.first { $0.key == key }?.name ?? key
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
