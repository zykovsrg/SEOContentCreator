import SwiftUI
import AppKit

/// Merged view of everything that ends up in this stage's prompt: the shared
/// role mandate and context blocks (system part), the stage's own prompt
/// (user part), model parameters, and a read-only preview of the assembled
/// result — in the same order the real request is built (`RoleContextAssembler`
/// + `PromptBuilder`).
struct StagePromptEditorView: View {
    @Bindable var template: StageTemplate
    var role: AIRole?
    let blocks: [ContextBlock]
    let allRoles: [AIRole]

    @AppStorage("openAIModel") private var settingsModel = "gpt-4.1"

    @State private var user = ""
    @State private var modelName = ""
    @State private var temperature = 0.6
    @State private var maxTokens = 8000
    /// Empty string = "по умолчанию" (nil, parameter omitted).
    @State private var reasoningEffort = ""
    @State private var savedNote: String?
    @State private var showSandbox = false
    @State private var showFactoryRestoreConfirmation = false
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var insertionToken = ""
    @State private var insertionRequestID = 0

    @State private var mandate = ""
    @State private var enabledBlockKeys: Set<String> = []
    @State private var blockTexts: [String: String] = [:]

    private var stage: PipelineStage {
        template.stage ?? .draft
    }

    private var activeModelName: String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? settingsModel : trimmed
    }

    private var normalizedReasoningEffort: String? {
        guard OpenAIClient.usesMaxCompletionTokens(model: activeModelName),
              !reasoningEffort.isEmpty
        else { return nil }
        return reasoningEffort
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
        .navigationTitle(stage.title)
        .onAppear(perform: load)
        .sheet(isPresented: $showSandbox) {
            TemplateSandboxSheet(
                stage: stage,
                template: sandboxTemplate()
            )
        }
        .confirmationDialog(
            "Вернуть стандарт приложения?",
            isPresented: $showFactoryRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Загрузить стандарт приложения") { restoreFactoryDefault() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Изменения пока попадут только в редактор. Если затем нажать «Сохранить», общая роль и контекстные блоки изменятся также в связанных этапах.")
        }
    }

    private var editorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if role != nil {
                    roleSection
                    Divider()
                    blocksSection
                    Divider()
                }
                stagePromptSection
                Divider()
                previewSection
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                bottomBar
            }
            .background(.regularMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Шаблоны › Этапы › \(stage.title)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Text(stage.title)
                    .font(.title)
                    .fontWeight(.bold)
                Text(stage.agentName)
                    .font(.callout).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("версия \(template.templateVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Здесь собраны все части промта, который уходит модели: роль, контекстные блоки и промт этапа — в том же порядке.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    // MARK: - Role (system)

    private var roleSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                if let role, !roleStageTitles.isEmpty {
                    SharedUsagePlaque(text: "Общее · используется в этапах: \(roleStageTitles.joined(separator: ", "))")
                }
                TextEditor(text: $mandate)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.top, 8)
        } label: {
            SectionLabel("Роль", subtitle: role?.name)
        }
        .padding(18)
    }

    private var roleStageTitles: [String] {
        guard let role else { return [] }
        return PromptCompositionUsage.stageTitles(forRoleKey: role.key)
    }

    // MARK: - Context blocks (system)

    private var blocksSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(blocks) { block in
                    blockRow(block)
                }
            }
            .padding(.top, 8)
        } label: {
            SectionLabel("Контекстные блоки", subtitle: "\(enabledBlockKeys.count) из \(blocks.count) включено")
        }
        .padding(18)
    }

    private func blockRow(_ block: ContextBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: blockToggleBinding(block.key)) {
                Text(block.title).font(.callout.weight(.semibold))
            }
            .toggleStyle(.checkbox)

            let usedBy = PromptCompositionUsage.roleNames(forBlockKey: block.key, in: allRoles)
            if !usedBy.isEmpty {
                SharedUsagePlaque(text: "Общее · используется ролями: \(usedBy.joined(separator: ", "))")
            }

            TextEditor(text: blockTextBinding(block.key))
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 90)
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func blockToggleBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { enabledBlockKeys.contains(key) },
            set: { isOn in
                if isOn { enabledBlockKeys.insert(key) } else { enabledBlockKeys.remove(key) }
            }
        )
    }

    private func blockTextBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { blockTexts[key] ?? "" },
            set: { blockTexts[key] = $0 }
        )
    }

    // MARK: - Stage prompt (user)

    private var stagePromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Промт этапа", subtitle: nil)
            PromptTemplateTextEditor(
                text: $user,
                selectedRange: $selectedRange,
                insertionToken: insertionToken,
                insertionRequestID: insertionRequestID
            )
            .frame(minHeight: 320)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }

    // MARK: - Preview

    private var previewSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                previewBlock(title: "SYSTEM", text: previewSystem)
                previewBlock(title: "USER", text: previewUser)
                Button {
                    copyPreviewToClipboard()
                } label: {
                    Label("Скопировать", systemImage: "doc.on.doc")
                }
            }
            .padding(.top, 8)
        } label: {
            SectionLabel("Итоговый промт", subtitle: "как уйдёт в \(stage.agentName)")
        }
        .padding(18)
    }

    private func previewBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "(пусто)" : text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Assembled exactly like a real run: transient (non-inserted) role and
    /// blocks built from the same unsaved editor state, passed through the
    /// same `RoleContextAssembler` that `StageExecutor` uses.
    private var previewSystem: String {
        guard let role else { return "" }
        let transientRole = AIRole(
            key: role.key,
            name: role.name,
            mandate: mandate,
            blockKeys: orderedEnabledBlockKeys()
        )
        let transientBlocks = blocks.map { block in
            ContextBlock(key: block.key, title: block.title, text: blockTexts[block.key] ?? block.text)
        }
        return RoleContextAssembler.assemble(role: transientRole, blocks: transientBlocks)
    }

    private var previewUser: String { user }

    private func copyPreviewToClipboard() {
        let combined = "SYSTEM:\n\(previewSystem)\n\nUSER:\n\(previewUser)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
    }

    // MARK: - Side panel (model params + variables)

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                generationSection
                Divider()
                variablesSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var generationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorPanelTitle("Параметры генерации")
            VStack(alignment: .leading, spacing: 6) {
                Text("Модель")
                    .foregroundStyle(.secondary)
                TextField("gpt-5.5", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .onChange(of: modelName) { _, _ in
                        if !OpenAIClient.usesMaxCompletionTokens(model: activeModelName) {
                            reasoningEffort = ""
                        }
                    }
            }
            if OpenAIClient.supportsTemperature(model: activeModelName) {
                Stepper(value: $temperature, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Температура")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(temperature, format: .number.precision(.fractionLength(1)))
                            .fontWeight(.semibold)
                    }
                }
            } else {
                HStack {
                    Text("Температура")
                        .foregroundStyle(.secondary)
                    Spacer()
                    MetaChip(text: "—")
                }
            }
            Stepper(value: $maxTokens, in: 1000...32000, step: 1000) {
                HStack {
                    Text("Max tokens")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(maxTokens.formatted(.number.grouping(.automatic)))
                        .fontWeight(.semibold)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Мышление")
                    .foregroundStyle(.secondary)
                Picker("Мышление", selection: $reasoningEffort) {
                    Text("Авто").tag("")
                    Text("Low").tag("low")
                    Text("Mid").tag("medium")
                    Text("High").tag("high")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!OpenAIClient.usesMaxCompletionTokens(model: activeModelName))
            }
        }
    }

    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorPanelTitle("Переменные · клик вставляет в промт")
            ForEach(TemplateVariables.all) { variable in
                Button {
                    insert(variable.token)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(variable.token)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor)
                        Text("\(variable.description) · \(variable.source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Text("Использованные в промте переменные подсвечиваются в редакторе.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Сбросить к моему дефолту", action: restorePersonalDefault)
                .foregroundStyle(.secondary)
                .disabled(PromptPersonalDefaultsService.personalDefaultState(
                    template: template, role: role, blocks: blocks
                ) == nil)
            Button("Вернуть стандарт приложения") {
                showFactoryRestoreConfirmation = true
            }
            .foregroundStyle(.secondary)
            Spacer()
            if let savedNote {
                Text(savedNote).font(.callout).foregroundStyle(.green)
            }
            Button {
                showSandbox = true
            } label: {
                Label("Песочница", systemImage: "play.fill")
            }
            Button("Сохранить", action: save)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    private func insert(_ token: String) {
        insertionToken = token
        insertionRequestID += 1
    }

    private var editorState: PromptEditorState {
        PromptEditorState(
            userPromptTemplate: user,
            modelName: activeModelName,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoningEffort: normalizedReasoningEffort,
            mandate: mandate,
            enabledBlockKeys: orderedEnabledBlockKeys(),
            blockTexts: blockTexts
        )
    }

    private func apply(_ state: PromptEditorState) {
        user = state.userPromptTemplate
        modelName = state.modelName
        temperature = state.temperature
        maxTokens = state.maxTokens
        reasoningEffort = state.reasoningEffort ?? ""
        mandate = state.mandate
        enabledBlockKeys = Set(state.enabledBlockKeys)
        blockTexts = state.blockTexts
    }

    private func load() {
        apply(PromptPersonalDefaultsService.liveState(template: template, role: role, blocks: blocks))
    }

    private func save() {
        PromptPersonalDefaultsService.saveAsPersonalDefault(
            editorState,
            template: template,
            role: role,
            blocks: blocks
        )
        savedNote = "Сохранено как мой дефолт · версия \(template.templateVersion)"
    }

    private func sandboxTemplate() -> StageTemplate {
        StageTemplate(
            stage: stage,
            articleType: template.articleTypeRaw.flatMap(ArticleType.init(rawValue:)),
            userPromptTemplate: user,
            modelName: activeModelName,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoningEffort: normalizedReasoningEffort,
            templateVersion: template.templateVersion
        )
    }

    private func restorePersonalDefault() {
        guard let state = PromptPersonalDefaultsService.personalDefaultState(
            template: template,
            role: role,
            blocks: blocks
        ) else { return }
        apply(state)
        savedNote = "Загружен мой дефолт · нажмите «Сохранить»"
    }

    private func restoreFactoryDefault() {
        apply(PromptPersonalDefaultsService.factoryState(stage: stage, role: role, blocks: blocks))
        savedNote = "Загружен стандарт приложения · нажмите «Сохранить»"
    }

    private func orderedEnabledBlockKeys() -> [String] {
        let canonical = ContextBlockDefaults.canonicalOrder.filter { enabledBlockKeys.contains($0) }
        let extra = blocks
            .map(\.key)
            .filter { enabledBlockKeys.contains($0) && !canonical.contains($0) }
        return canonical + extra
    }
}

private struct SectionLabel: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SharedUsagePlaque: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
}
