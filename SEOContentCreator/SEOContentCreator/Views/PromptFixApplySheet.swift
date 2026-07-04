import SwiftUI

/// Lets the user apply a `PromptRecommendation` to a stage's user prompt.
/// Shows the current prompt with the recommendation merged in (diff-highlighted,
/// reusing `ParagraphDiff`), editable before saving. Nothing is written to
/// `StageTemplate` until the user explicitly taps "Сохранить в шаблон".
struct PromptFixApplySheet: View {
    @Environment(\.dismiss) private var dismiss
    var recommendation: PromptRecommendation
    var templates: [StageTemplate]

    @State private var selectedTemplateID: UUID?
    @State private var draft: String = ""
    @State private var savedNote: String?

    private var sortedTemplates: [StageTemplate] {
        templates
            .filter { $0.stage != nil && $0.stage != .images }
            .sorted { order($0.stageRaw) < order($1.stageRaw) }
    }

    private var selectedTemplate: StageTemplate? {
        sortedTemplates.first { $0.uuid == selectedTemplateID }
    }

    private var originalText: String { selectedTemplate?.userPromptTemplate ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Применить правку").font(.title2).bold()
                Spacer()
                Button("Закрыть") { dismiss() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.problem).font(.headline)
                Text(recommendation.suggestion).font(.body).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)

            Picker("Этап", selection: $selectedTemplateID) {
                ForEach(sortedTemplates) { t in
                    Text(t.stage?.title ?? t.stageRaw).tag(Optional(t.uuid))
                }
            }
            .frame(maxWidth: 360)
            .onChange(of: selectedTemplateID) { _, _ in resetDraft() }

            Text("Было / станет — правка выделена цветом").font(.headline)
            ScrollView {
                diffPreview.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .border(.gray.opacity(0.3))

            Text("Пользовательский промт этапа — отредактируйте перед сохранением").font(.headline)
            TextEditor(text: $draft).frame(minHeight: 200).border(.gray.opacity(0.3))

            HStack {
                Button("Сохранить в шаблон") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTemplate == nil)
                Spacer()
                if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
            }
        }
        .padding()
        .frame(width: 640, height: 640)
        .onAppear(perform: setup)
    }

    @ViewBuilder private var diffPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ParagraphDiff.diff(old: originalText, new: draft).enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(tint(for: line.kind))
            }
        }
        .textSelection(.enabled)
    }

    private func tint(for kind: ParagraphDiffKind) -> Color {
        switch kind {
        case .added:     return .green.opacity(0.18)
        case .removed:   return .red.opacity(0.18)
        case .unchanged: return .clear
        }
    }

    private func order(_ raw: String) -> Int {
        PipelineStage.allCases.firstIndex { $0.rawValue == raw } ?? Int.max
    }

    private func setup() {
        if selectedTemplateID == nil {
            selectedTemplateID = guessTemplate()?.uuid ?? sortedTemplates.first?.uuid
        }
        resetDraft()
    }

    /// `recommendation.location` is free-form AI text (e.g. "«Финальная вычитка»"),
    /// not a structured link — match it against stage titles as a best-effort default.
    private func guessTemplate() -> StageTemplate? {
        sortedTemplates.first { t in
            guard let title = t.stage?.title else { return false }
            return recommendation.location.localizedCaseInsensitiveContains(title)
        }
    }

    private func resetDraft() {
        guard let selectedTemplate else { return }
        draft = selectedTemplate.userPromptTemplate + "\n\n" + recommendation.suggestion
    }

    private func save() {
        guard let selectedTemplate else { return }
        selectedTemplate.userPromptTemplate = draft
        selectedTemplate.templateVersion += 1
        selectedTemplate.updatedAt = .now
        savedNote = "Сохранено (версия \(selectedTemplate.templateVersion))"
    }
}
