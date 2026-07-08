import SwiftUI
import SwiftData

private enum EditorRewriteMode: String, CaseIterable, Identifiable {
    case skill
    case comment

    var id: String { rawValue }
    var title: String { self == .skill ? "Скилл" : "Свой комментарий" }
}

struct TopicEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    var onBack: () -> Void

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @Query(sort: \SkillPreset.order) private var skills: [SkillPreset]

    @State private var text = ""
    @State private var sessionState: EditorSessionState = .editing
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var pendingOriginalFragment = ""
    @State private var rewriteMode: EditorRewriteMode = .skill
    @State private var fragmentComment = ""
    @State private var selectedSkillID: UUID?
    @State private var editor = FragmentEditor.live()
    @State private var commercialBlockRequestID = 0
    @State private var commandRequestID = 0
    @State private var command: MarkdownEditorCommand = .none

    private var originalText: String {
        topic.currentVersion?.text ?? ""
    }

    private var metrics: EditorMetrics {
        EditorMetrics.compute(text: text, targetVolume: topic.targetVolume)
    }

    var body: some View {
        VStack(spacing: 0) {
            windowTitleBar
            HStack(spacing: 10) {
                documentPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .panelCard()
                toolsPanel
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
                    .panelCard()
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground)
        .navigationTitle("\(topic.title) · Редактура")
        .onAppear {
            text = originalText
            if selectedSkillID == nil { selectedSkillID = skills.first?.uuid }
        }
    }

    private var windowTitleBar: some View {
        HStack {
            Spacer()
            Text("‹ \(topic.title) · Редактура")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 10)
        .background(Color.panelFill)
    }

    private var documentPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    onBack()
                } label: {
                    Label("К теме", systemImage: "chevron.left")
                }
                .disabled(!canLeave)

                Text("Редактура")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("изменения сохранятся как новая версия")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
            formatToolbar
            Divider()

            editorStatusBanners

            MarkdownTextEditor(
                text: $text,
                font: .systemFont(ofSize: 17),
                isEditable: sessionState.isTextEditable,
                onSelectionChange: { range, _ in
                    selectedRange = range
                },
                highlightRange: highlightRange,
                commercialBlockRequestID: commercialBlockRequestID,
                commandRequestID: commandRequestID,
                command: command
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if case .reviewing = sessionState {
                fragmentReviewBar
                Divider()
            }

            bottomBar
        }
    }

    private var formatToolbar: some View {
        HStack(spacing: 8) {
            formatButton("B", help: "Жирный") { apply(.bold) }
                .fontWeight(.bold)
            formatButton("/", help: "Курсив") { apply(.italic) }
                .italic()
            toolbarDivider
            formatButton("H1", help: "Заголовок 1") { apply(.heading(1)) }
            formatButton("H2", help: "Заголовок 2") { apply(.heading(2)) }
            formatButton("H3", help: "Заголовок 3") { apply(.heading(3)) }
            toolbarDivider
            Button {
                apply(.bulletList)
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 34, height: 28)
            }
            .buttonStyle(.plain)
            .help("Список")
            toolbarDivider
            Button {
                commercialBlockRequestID += 1
            } label: {
                Text("[Комм. блок]")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Коммерческий блок")

            Spacer()
            Text("\(metrics.charactersWithSpaces.formatted())")
                .font(.callout)
                .fontWeight(.semibold)
            Text("/ \(topic.targetVolume?.formatted() ?? "—") знаков")
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView(value: metrics.progress ?? 0)
                .frame(width: 110)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }

    private func formatButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .fontWeight(.semibold)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var editorStatusBanners: some View {
        if let error = editor.lastErrorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                Text(error).font(.callout)
                Spacer()
                Button("Скрыть") { editor.lastErrorMessage = nil }
            }
            .padding(10)
            .background(Color.red.opacity(0.12))
            Divider()
        }
        if let warning = editor.lastWarningMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(warning).font(.callout)
                Spacer()
                Button("Скрыть") { editor.lastWarningMessage = nil }
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            Divider()
        }
    }

    private var fragmentReviewBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ИИ-правка · осталось принять или отклонить")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                Text(pendingOriginalFragment)
                    .strikethrough()
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.red.opacity(0.12))
                if case .reviewing(_, let proposed) = sessionState {
                    Text(proposed)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.green.opacity(0.12))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Отклонить", role: .destructive, action: rejectFragment)
                Button("Принять", action: acceptFragment)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Отмена (Esc)") { onBack() }
                .keyboardShortcut(.cancelAction)
                .disabled(!canLeave)
                .foregroundStyle(.secondary)
            Spacer()
            if hasChanges {
                Label("Есть несохранённые изменения", systemImage: "circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Button("Сохранить как новую версию", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(16)
    }

    private var toolsPanel: some View {
        VStack(spacing: 0) {
            rewriteTools
            Divider()
            metricsPanel
            Divider()
            shortcutsPanel
        }
    }

    private var rewriteTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Переписать выделенное · ✨")
            Picker("Режим", selection: $rewriteMode) {
                ForEach(EditorRewriteMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if rewriteMode == .skill {
                VStack(spacing: 8) {
                    ForEach(skills) { skill in
                        Button {
                            selectedSkillID = skill.uuid
                        } label: {
                            Text(skill.name)
                                .fontWeight(selectedSkillID == skill.uuid ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    selectedSkillID == skill.uuid ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                TextEditor(text: $fragmentComment)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                startRegenerate()
            } label: {
                Label(editor.isRunning ? "Переписываю..." : "Переписать фрагмент", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!canStartRegenerate)

            Text("Выделите текст в документе — панель активна, когда есть выделение. Результат придёт как сравнение «было/стало».")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var metricsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Объём")
            metricRow("Знаков (с пробелами)", metrics.charactersWithSpaces.formatted())
            metricRow("Целевой объём из брифа", topic.targetVolume?.formatted() ?? "—")
            metricRow("Слов", metrics.words.formatted())
            metricRow("Коммерческих блоков", metrics.commercialBlocks.formatted())
        }
        .padding(16)
    }

    private var shortcutsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Горячие клавиши")
            metricRow("Жирный / курсив", "⌘B / ⌘I")
            metricRow("Заголовок 1–3", "⌘⌥1–3")
            metricRow("Коммерческий блок", "⌘⇧K")
            metricRow("Переписать выделенное", "⌘R")
        }
        .padding(16)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.callout)
    }

    private var canLeave: Bool {
        EditorSessionState.canCloseSheet(state: sessionState)
    }

    private var canStartRegenerate: Bool {
        guard EditorSessionState.canTriggerRegenerate(state: sessionState, hasNonEmptySelection: selectedRange.length > 0),
              !editor.isRunning
        else { return false }
        switch rewriteMode {
        case .skill:
            return selectedSkillID != nil
        case .comment:
            return !fragmentComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var highlightRange: NSRange? {
        if case .reviewing(let range, _) = sessionState { return range }
        return nil
    }

    private var hasChanges: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && text != originalText
    }

    private var canSave: Bool {
        sessionState == .editing && hasChanges
    }

    private func apply(_ nextCommand: MarkdownEditorCommand) {
        command = nextCommand
        commandRequestID += 1
    }

    private func startRegenerate() {
        let ns = text as NSString
        guard selectedRange.length > 0,
              selectedRange.location + selectedRange.length <= ns.length
        else { return }
        let fragment = ns.substring(with: selectedRange)

        let instruction: String
        let source: VersionSource
        let roleKey: String
        switch rewriteMode {
        case .skill:
            guard let skill = skills.first(where: { $0.uuid == selectedSkillID }) else { return }
            instruction = skill.prompt
            source = .skillApplied
            roleKey = skill.roleKey
        case .comment:
            instruction = "Перепиши фрагмент с учётом замечания: \(fragmentComment)"
            source = .fragmentRegenerated
            roleKey = "author"
        }

        pendingOriginalFragment = fragment
        let range = selectedRange
        sessionState = .generating(range: range)

        Task {
            await editor.run(
                fragment: fragment,
                instruction: instruction,
                roleKey: roleKey,
                model: model,
                temperature: 0.6,
                maxTokens: 4000,
                source: source,
                topic: topic,
                in: context
            )
            guard let rewritten = editor.rewrittenFragment else {
                sessionState = .editing
                return
            }
            text = (text as NSString).replacingCharacters(in: range, with: rewritten)
            let newRange = NSRange(location: range.location, length: (rewritten as NSString).length)
            sessionState = .reviewing(range: newRange, proposedText: rewritten)
        }
    }

    private func acceptFragment() {
        guard case .reviewing = sessionState else { return }
        sessionState = .editing
    }

    private func rejectFragment() {
        guard case .reviewing(let range, _) = sessionState else { return }
        text = (text as NSString).replacingCharacters(in: range, with: pendingOriginalFragment)
        sessionState = .editing
    }

    private func save() {
        VersionActions.applyManualEdit(topic: topic, newText: text, in: context)
        onBack()
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.bold)
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }
}
