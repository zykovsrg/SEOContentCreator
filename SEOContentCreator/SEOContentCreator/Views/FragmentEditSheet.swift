import SwiftUI
import SwiftData
import AppKit

private enum FragmentMode: String, CaseIterable, Identifiable {
    case skill
    case comment
    var id: String { rawValue }
    var title: String { self == .skill ? "Скилл" : "Свой комментарий" }
}

struct FragmentEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @Query(sort: \SkillPreset.order) private var skills: [SkillPreset]

    @State private var mode: FragmentMode = .skill
    @State private var fragment = ""
    @State private var comment = ""
    @State private var selectedSkillID: UUID?
    @State private var editor = FragmentEditor.live()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Правка фрагмента").font(.headline)

            if editor.proposedText == nil {
                inputForm
            } else {
                preview
            }
        }
        .padding()
        .frame(width: 720, height: 560)
        .onAppear(perform: prefillFromClipboard)
    }

    // MARK: Input

    @ViewBuilder private var inputForm: some View {
        Picker("Режим", selection: $mode) {
            ForEach(FragmentMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        Text("Фрагмент").font(.caption).foregroundStyle(.secondary)
        TextEditor(text: $fragment)
            .frame(minHeight: 90)
            .border(Color.secondary.opacity(0.3))

        if mode == .skill {
            Text("Скилл").font(.caption).foregroundStyle(.secondary)
            List(selection: $selectedSkillID) {
                ForEach(skills) { skill in
                    Text(skill.name).tag(Optional(skill.uuid))
                }
            }
            .frame(minHeight: 140)
        } else {
            Text("Что не нравится").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $comment)
                .frame(minHeight: 90)
                .border(Color.secondary.opacity(0.3))
        }

        if let error = editor.lastErrorMessage {
            Text(error).font(.callout).foregroundStyle(.red)
        }

        HStack {
            Button("Отмена") { dismiss() }
            Spacer()
            if editor.isRunning {
                ProgressView().controlSize(.small)
            }
            Button("Применить", action: run)
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
        }
    }

    private var canRun: Bool {
        guard !fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(editor.isRunning) else { return false }
        switch mode {
        case .skill:   return selectedSkillID != nil
        case .comment: return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        SideBySideView(
            leftText: topic.currentVersion?.text,
            rightText: editor.proposedText,
            isStreaming: false
        )
        .border(Color.secondary.opacity(0.2))

        HStack {
            Button("Отклонить", role: .destructive) { editor.proposedText = nil }
            Spacer()
            Button("Принять") {
                editor.accept(topic: topic, in: context)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Actions

    private func prefillFromClipboard() {
        if fragment.isEmpty, let clip = NSPasteboard.general.string(forType: .string) {
            fragment = clip
        }
    }

    private func run() {
        let fullText = topic.currentVersion?.text ?? ""
        let (instruction, source, roleKey): (String, VersionSource, String)
        switch mode {
        case .skill:
            guard let skill = skills.first(where: { $0.uuid == selectedSkillID }) else { return }
            instruction = skill.prompt
            source = .skillApplied
            roleKey = skill.roleKey
        case .comment:
            instruction = "Перепиши фрагмент с учётом замечания: \(comment)"
            source = .fragmentRegenerated
            roleKey = "author"
        }
        Task {
            await editor.run(
                fullText: fullText, fragment: fragment, instruction: instruction,
                source: source, roleKey: roleKey, model: model,
                temperature: 0.6, maxTokens: 4000, topic: topic, in: context
            )
        }
    }
}
