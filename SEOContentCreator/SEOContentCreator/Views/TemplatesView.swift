import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

private enum TemplateSelection: Hashable {
    case stage(UUID)
    case role(UUID)
    case block(UUID)
    case imagePrompt(UUID)
    case imagePreset(UUID)
}

struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query private var templates: [StageTemplate]
    @Query private var roles: [AIRole]
    @Query private var blocks: [ContextBlock]
    @Query private var imagePrompts: [ImagePromptTemplate]
    @Query private var imagePresets: [ImageStylePreset]
    @State private var selection: TemplateSelection?

    private var sortedTemplates: [StageTemplate] {
        templates.sorted { lhs, rhs in
            order(lhs.stageRaw) < order(rhs.stageRaw)
        }
    }

    private var sortedRoles: [AIRole] {
        roles.sorted { lhs, rhs in
            roleOrder(lhs.key) < roleOrder(rhs.key)
        }
    }

    private var sortedBlocks: [ContextBlock] {
        blocks.sorted { lhs, rhs in
            blockOrder(lhs.key) < blockOrder(rhs.key)
        }
    }

    private var sortedImagePrompts: [ImagePromptTemplate] {
        imagePrompts.sorted { lhs, rhs in
            imagePromptOrder(lhs.kindRaw) < imagePromptOrder(rhs.kindRaw)
        }
    }

    private var sortedImagePresets: [ImageStylePreset] {
        imagePresets.sorted { $0.createdAt < $1.createdAt }
    }

    private func order(_ raw: String) -> Int {
        PipelineStage.allCases.firstIndex { $0.rawValue == raw } ?? Int.max
    }

    private func roleOrder(_ key: String) -> Int {
        RoleDefaults.all.firstIndex { $0.key == key } ?? Int.max
    }

    private func blockOrder(_ key: String) -> Int {
        ContextBlockDefaults.canonicalOrder.firstIndex(of: key) ?? Int.max
    }

    private func imagePromptOrder(_ raw: String) -> Int {
        ImagePromptKind.allCases.firstIndex { $0.rawValue == raw } ?? Int.max
    }

    private var selectedTemplate: StageTemplate? {
        guard case .stage(let id) = selection else { return nil }
        return templates.first { $0.uuid == id }
    }

    private var selectedRole: AIRole? {
        guard case .role(let id) = selection else { return nil }
        return roles.first { $0.uuid == id }
    }

    private var selectedBlock: ContextBlock? {
        guard case .block(let id) = selection else { return nil }
        return blocks.first { $0.uuid == id }
    }

    private var selectedImagePrompt: ImagePromptTemplate? {
        guard case .imagePrompt(let id) = selection else { return nil }
        return imagePrompts.first { $0.uuid == id }
    }

    private var selectedImagePreset: ImageStylePreset? {
        guard case .imagePreset(let id) = selection else { return nil }
        return imagePresets.first { $0.uuid == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                Section("Промты этапов") {
                    ForEach(sortedTemplates) { t in
                        Text(t.stage?.title ?? t.stageRaw).tag(TemplateSelection.stage(t.uuid))
                    }
                }

                Section("ИИ-роли") {
                    ForEach(sortedRoles) { role in
                        Text(role.name).tag(TemplateSelection.role(role.uuid))
                    }
                }

                Section("Редполитика и источники") {
                    ForEach(sortedBlocks) { block in
                        Text(block.title).tag(TemplateSelection.block(block.uuid))
                    }
                }

                Section("Изображения") {
                    ForEach(sortedImagePrompts) { template in
                        Text("Промт: \(template.kind?.title ?? template.kindRaw)")
                            .tag(TemplateSelection.imagePrompt(template.uuid))
                    }
                    ForEach(sortedImagePresets) { preset in
                        Text("Пресет: \(preset.name)")
                            .tag(TemplateSelection.imagePreset(preset.uuid))
                    }
                    Button {
                        let preset = ImageStylePreset(name: "Новый пресет", styleText: "")
                        context.insert(preset)
                        selection = .imagePreset(preset.uuid)
                    } label: {
                        Label("Добавить пресет", systemImage: "plus")
                    }
                }
            }
            .frame(width: 260)
            Divider()
            detail
        }
        .navigationTitle("Шаблоны")
        .onAppear(perform: ensureSelection)
        .onChange(of: templates.map(\.uuid)) { _, _ in ensureSelection() }
        .onChange(of: roles.map(\.uuid)) { _, _ in ensureSelection() }
        .onChange(of: blocks.map(\.uuid)) { _, _ in ensureSelection() }
        .onChange(of: imagePrompts.map(\.uuid)) { _, _ in ensureSelection() }
        .onChange(of: imagePresets.map(\.uuid)) { _, _ in ensureSelection() }
    }

    @ViewBuilder
    private var detail: some View {
        if let t = selectedTemplate {
            TemplateEditorView(template: t).id(t.uuid)
        } else if let role = selectedRole {
            RoleEditorView(role: role, blocks: sortedBlocks).id(role.uuid)
        } else if let block = selectedBlock {
            ContextBlockEditorView(block: block, roles: sortedRoles).id(block.uuid)
        } else if let prompt = selectedImagePrompt {
            ImagePromptEditorView(template: prompt).id(prompt.uuid)
        } else if let preset = selectedImagePreset {
            ImageStylePresetEditorView(preset: preset) { selection = nil }.id(preset.uuid)
        } else {
            ContentUnavailableView("Выберите шаблон", systemImage: "doc.text")
        }
    }

    private func ensureSelection() {
        if selection != nil { return }
        if let first = sortedTemplates.first {
            selection = .stage(first.uuid)
        } else if let first = sortedRoles.first {
            selection = .role(first.uuid)
        } else if let first = sortedBlocks.first {
            selection = .block(first.uuid)
        } else if let first = sortedImagePrompts.first {
            selection = .imagePrompt(first.uuid)
        } else if let first = sortedImagePresets.first {
            selection = .imagePreset(first.uuid)
        }
    }
}

private struct TemplateEditorView: View {
    @Bindable var template: StageTemplate

    @State private var system = ""
    @State private var user = ""
    @State private var model = "gpt-4.1"
    @State private var temperature = 0.6
    @State private var maxTokens = 8000
    /// Empty string = "по умолчанию" (nil, parameter omitted).
    @State private var reasoningEffort = ""
    @State private var showVariables = false
    @State private var savedNote: String?

    private let models = [
        "gpt-5.5-pro", "gpt-5.5",
        "gpt-5.4-pro", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano",
        "gpt-5.3-chat-latest",
        "gpt-4.1", "gpt-4o", "gpt-4o-mini"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(template.stage?.title ?? template.stageRaw).font(.title2).bold()
                Text("Версия шаблона: \(template.templateVersion)")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Дополнение к системному промту этапа").font(.headline)
                Text("Основная роль и общие правила берутся из разделов «ИИ-роли» и «Редполитика и источники».")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $system).frame(minHeight: 120).border(.gray.opacity(0.3))

                Text("Пользовательский промт (инструкция с переменными)").font(.headline)
                TextEditor(text: $user).frame(minHeight: 200).border(.gray.opacity(0.3))

                Text("Параметры модели").font(.headline)
                Picker("Модель", selection: $model) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 360, alignment: .leading)
                Stepper("Температура: \(temperature, specifier: "%.1f")",
                        value: $temperature, in: 0...1, step: 0.1)
                    .frame(maxWidth: 360, alignment: .leading)
                Stepper("Max tokens: \(maxTokens)", value: $maxTokens, in: 1000...16000, step: 1000)
                    .frame(maxWidth: 360, alignment: .leading)

                if OpenAIClient.usesMaxCompletionTokens(model: model) {
                    Picker("Интенсивность мышления", selection: $reasoningEffort) {
                        Text("По умолчанию").tag("")
                        Text("Низкая").tag("low")
                        Text("Средняя").tag("medium")
                        Text("Высокая").tag("high")
                    }
                    .frame(maxWidth: 360, alignment: .leading)
                    Text("Влияет только на модели GPT-5 / o-серии: чем выше, тем дольше и тщательнее модель «обдумывает» ответ.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                DisclosureGroup("Переменные {{…}}", isExpanded: $showVariables) {
                    ForEach(TemplateVariables.all) { v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.token).font(.system(.callout, design: .monospaced)).bold()
                            Text("\(v.description) · источник: \(v.source)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }

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

    private func load() {
        system = template.systemPrompt
        user = template.userPromptTemplate
        model = template.modelName
        temperature = template.temperature
        maxTokens = template.maxTokens
        reasoningEffort = template.reasoningEffort ?? ""
    }

    private func save() {
        template.systemPrompt = system
        template.userPromptTemplate = user
        template.modelName = model
        template.temperature = temperature
        template.maxTokens = maxTokens
        // Persist only when the model supports it and a level is chosen; otherwise clear it.
        template.reasoningEffort = (OpenAIClient.usesMaxCompletionTokens(model: model) && !reasoningEffort.isEmpty)
            ? reasoningEffort : nil
        template.templateVersion += 1
        template.updatedAt = .now
        savedNote = "Сохранено (версия \(template.templateVersion))"
    }

    private func resetToDefault() {
        let c = StageTemplateDefaults.content(for: template.stage ?? .draft)
        system = c.systemPrompt
        user = c.userPromptTemplate
        model = c.modelName
        temperature = c.temperature
        maxTokens = c.maxTokens
        reasoningEffort = ""
        save()
        savedNote = "Сброшено к стандартному"
    }
}

private struct RoleEditorView: View {
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

private struct ContextBlockEditorView: View {
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

private struct ImagePromptEditorView: View {
    @Bindable var template: ImagePromptTemplate
    @State private var text = ""
    @State private var showVariables = false
    @State private var savedNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Промт изображения: \(template.kind?.title ?? template.kindRaw)").font(.title2).bold()
                Text("Стиль (палитра, ограничения) задаётся в пресете и добавляется к промту автоматически.")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Шаблон сюжета (с переменными)").font(.headline)
                TextEditor(text: $text).frame(minHeight: 200).border(.gray.opacity(0.3))

                DisclosureGroup("Переменные {{…}}", isExpanded: $showVariables) {
                    ForEach(TemplateVariables.all) { variable in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variable.token).font(.system(.callout, design: .monospaced)).bold()
                            Text("\(variable.description) · источник: \(variable.source)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }

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
        .onAppear { text = template.userPromptTemplate }
    }

    private func save() {
        template.userPromptTemplate = text
        template.updatedAt = .now
        savedNote = "Сохранено"
    }

    private func resetToDefault() {
        guard let kind = template.kind else { return }
        text = ImagePromptDefaults.content(for: kind)
        save()
        savedNote = "Сброшено к стандартному"
    }
}

private struct ImageStylePresetEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var preset: ImageStylePreset
    var onDelete: () -> Void

    @State private var name = ""
    @State private var styleText = ""
    @State private var size = "1024x1024"
    @State private var quality = "high"
    @State private var savedNote: String?

    private let sizes = ["1024x1024", "1536x1024", "1024x1536"]
    private let qualities = ["high", "medium", "low"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Пресет стиля").font(.title2).bold()

                TextField("Имя", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Text("Описание стиля (палитра, ограничения, аудитория)").font(.headline)
                TextEditor(text: $styleText).frame(minHeight: 200).border(.gray.opacity(0.3))

                Picker("Размер", selection: $size) {
                    ForEach(sizes, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 280, alignment: .leading)
                Picker("Качество", selection: $quality) {
                    ForEach(qualities, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 280, alignment: .leading)

                HStack(spacing: 8) {
                    Text("Референс-картинка:")
                    if preset.referenceImageData != nil {
                        Text("есть").foregroundStyle(.green)
                        Button("Удалить референс") { preset.referenceImageData = nil }
                    } else {
                        Text("нет").foregroundStyle(.secondary)
                    }
                    Button("Выбрать…") { pickReference() }
                }
                .font(.callout)

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    if preset.name == ImageStylePresetDefaults.name {
                        Button("Сбросить к стандартному") { resetToDefault() }
                    }
                    Spacer()
                    Button("Удалить пресет", role: .destructive) { deletePreset() }
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private func load() {
        name = preset.name
        styleText = preset.styleText
        size = preset.size
        quality = preset.quality
    }

    private func save() {
        preset.name = name
        preset.styleText = styleText
        preset.size = size
        preset.quality = quality
        preset.updatedAt = .now
        savedNote = "Сохранено"
    }

    private func resetToDefault() {
        styleText = ImageStylePresetDefaults.styleText
        name = ImageStylePresetDefaults.name
        save()
        savedNote = "Сброшено к стандартному"
    }

    private func deletePreset() {
        context.delete(preset)
        onDelete()
    }

    private func pickReference() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            preset.referenceImageData = data
        }
    }
}
