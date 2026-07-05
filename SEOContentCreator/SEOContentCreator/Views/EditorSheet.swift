import SwiftUI
import SwiftData

private enum FragmentMode: String, CaseIterable, Identifiable {
    case skill
    case comment
    var id: String { rawValue }
    var title: String { self == .skill ? "Скилл" : "Свой комментарий" }
}

struct EditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @Query(sort: \SkillPreset.order) private var skills: [SkillPreset]

    @State private var text = ""
    @State private var sessionState: EditorSessionState = .editing
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var selectionRect: CGRect?
    @State private var pendingOriginalFragment = ""

    @State private var showRegenerateCard = false
    @State private var fragmentMode: FragmentMode = .skill
    @State private var fragmentComment = ""
    @State private var selectedSkillID: UUID?
    @State private var editor = FragmentEditor.live()
    @State private var commercialBlockRequestID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Редактор").font(.headline)
                Spacer()
                if sessionState.isGenerating {
                    ProgressView().controlSize(.small)
                }
            }
            Text("Правка сохранится как новая версия и станет текущей, когда нажмёте «Сохранить». Выделите фрагмент и нажмите «Переписать», чтобы перегенерировать его через ИИ. Cmd+B — жирный, Cmd+I — курсив, Cmd+Option+1/2/3 — заголовок, Cmd+Shift+K — коммерческий блок (в рамке при публикации в Google Docs).")
                .font(.caption).foregroundStyle(.secondary)

            if let error = editor.lastErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                    Text(error).font(.callout)
                    Spacer()
                    Button("Скрыть") { editor.lastErrorMessage = nil }
                }
                .padding(8)
                .background(Color.red.opacity(0.12))
            }
            if let warning = editor.lastWarningMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(warning).font(.callout)
                    Spacer()
                    Button("Скрыть") { editor.lastWarningMessage = nil }
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
            }

            editorArea

            if case .reviewing = sessionState {
                HStack {
                    Spacer()
                    Button("Отклонить", role: .destructive, action: rejectFragment)
                    Button("Принять", action: acceptFragment).keyboardShortcut(.defaultAction)
                }
            }

            HStack {
                Button("Отмена") { dismiss() }
                    .disabled(!canCloseSheet)
                Spacer()
                Button("Перегенерировать выделенное") { showRegenerateCard = true }
                    .disabled(!canTriggerRegenerate)
                Button("Отметить как коммерческий блок") { commercialBlockRequestID += 1 }
                    .disabled(!canTriggerRegenerate)
                Button("Сохранить", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
        }
        .padding()
        .frame(minWidth: 720, idealWidth: 900, maxWidth: .infinity,
               minHeight: 560, idealHeight: 700, maxHeight: .infinity)
        .onAppear { text = topic.currentVersion?.text ?? "" }
    }

    // MARK: Editor area (text view + floating "Переписать" button + regenerate card)

    @ViewBuilder private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            MarkdownTextEditor(
                text: $text,
                font: .systemFont(ofSize: 15),
                isEditable: sessionState.isTextEditable,
                onSelectionChange: { range, rect in
                    selectedRange = range
                    selectionRect = rect
                },
                highlightRange: highlightRange,
                commercialBlockRequestID: commercialBlockRequestID
            )
            .frame(minWidth: 500, minHeight: 300)
            .border(Color.secondary.opacity(0.3))

            if canTriggerRegenerate, let rect = selectionRect {
                Button {
                    showRegenerateCard = true
                } label: {
                    Label("Переписать", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .offset(x: rect.minX, y: max(0, rect.minY - 30))
            }

            if showRegenerateCard, let rect = selectionRect {
                regenerateCard
                    .offset(x: rect.minX, y: rect.maxY + 6)
            }
        }
    }

    @ViewBuilder private var regenerateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Переписать выделенный фрагмент").font(.headline)

            Picker("Режим", selection: $fragmentMode) {
                ForEach(FragmentMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if fragmentMode == .skill {
                Text("Скилл").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(skills) { skill in
                            HStack {
                                Text(skill.name)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selectedSkillID == skill.uuid ? Color.accentColor.opacity(0.2) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedSkillID = skill.uuid }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 140)
                .border(Color.secondary.opacity(0.3))
            } else {
                Text("Что не нравится").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $fragmentComment)
                    .frame(minHeight: 70)
                    .border(Color.secondary.opacity(0.3))
            }

            HStack {
                Button("Отмена") { showRegenerateCard = false }
                Spacer()
                Button("Перегенерировать", action: startRegenerate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStartRegenerate)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    // MARK: Derived state

    private var canTriggerRegenerate: Bool {
        EditorSessionState.canTriggerRegenerate(state: sessionState, hasNonEmptySelection: selectedRange.length > 0)
    }

    private var canCloseSheet: Bool {
        EditorSessionState.canCloseSheet(state: sessionState)
    }

    private var canStartRegenerate: Bool {
        switch fragmentMode {
        case .skill:   return selectedSkillID != nil
        case .comment: return !fragmentComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var highlightRange: NSRange? {
        if case .reviewing(let range, _) = sessionState { return range }
        return nil
    }

    private var hasChanges: Bool {
        guard sessionState == .editing else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && text != (topic.currentVersion?.text ?? "")
    }

    // MARK: Actions

    private func startRegenerate() {
        let ns = text as NSString
        guard selectedRange.length > 0, selectedRange.location + selectedRange.length <= ns.length else { return }
        let fragment = ns.substring(with: selectedRange)

        let instruction: String
        let source: VersionSource
        let roleKey: String
        switch fragmentMode {
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
        showRegenerateCard = false

        Task {
            await editor.run(
                fragment: fragment, instruction: instruction, roleKey: roleKey,
                model: model, temperature: 0.6, maxTokens: 4000, source: source,
                topic: topic, in: context
            )
            guard let rewritten = editor.rewrittenFragment else {
                sessionState = .editing
                return
            }
            let updated = (text as NSString).replacingCharacters(in: range, with: rewritten)
            text = updated
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
        dismiss()
    }
}
