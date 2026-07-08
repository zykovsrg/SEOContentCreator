import Foundation
import SwiftUI

struct RoleEditorView: View {
    @Bindable var role: AIRole
    let blocks: [ContextBlock]

    @State private var name = ""
    @State private var mandate = ""
    @State private var selectedBlockKeys: Set<String> = []
    @State private var savedNote: String?
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var insertionToken = ""
    @State private var insertionRequestID = 0

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
        .navigationTitle(name.isEmpty ? role.name : name)
        .onAppear(perform: load)
    }

    private var editorPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PromptTemplateTextEditor(
                text: $mandate,
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
            Text("Шаблоны › Роли › \(name.isEmpty ? role.name : name)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Text("Роль")
                    .font(.title)
                    .fontWeight(.bold)
                Text("версия \(role.version)")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.controlSurface, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            TextField("Имя", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 460)

            Text("Установка роли задаёт общий характер ответа. Контекстные блоки добавляются отдельно справа.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                blocksSection
                Divider()
                stagesSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorPanelTitle("Использует блоки")
            ForEach(blocks) { block in
                Toggle(isOn: binding(for: block.key)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(block.title)
                            .font(.callout.weight(.semibold))
                        Text(block.key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Выбранные блоки добавляются к роли при генерации.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorPanelTitle("Отвечает за этапы")
            if stageTitles.isEmpty {
                Text("Нет закреплённых этапов")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stageTitles, id: \.self) { title in
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Сбросить к стандартному") { resetToDefault() }
                .foregroundStyle(.secondary)
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
