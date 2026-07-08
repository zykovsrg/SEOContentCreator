import SwiftUI
import Foundation

struct TemplateEditorView: View {
    @Bindable var template: StageTemplate
    @AppStorage("openAIModel") private var settingsModel = "gpt-4.1"

    @State private var user = ""
    @State private var temperature = 0.6
    @State private var maxTokens = 8000
    /// Empty string = "по умолчанию" (nil, parameter omitted).
    @State private var reasoningEffort = ""
    @State private var savedNote: String?
    @State private var showSandbox = false
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var insertionToken = ""
    @State private var insertionRequestID = 0

    private var stage: PipelineStage {
        template.stage ?? .draft
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
    }

    private var editorPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Шаблоны › Промты этапов › \(stage.title)")
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

                Text("Роль, общие правила и редполитика добавляются автоматически из разделов «Роли» и «Редполитика».")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(18)

            Divider()

            PromptTemplateTextEditor(
                text: $user,
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

    private var sidePanel: some View {
        VStack(spacing: 0) {
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
    }

    private var generationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TemplatePanelTitle("Параметры генерации")
            HStack {
                Text("Модель")
                    .foregroundStyle(.secondary)
                Spacer()
                MetaChip(text: settingsModel)
            }
            Stepper(value: $temperature, in: 0...1, step: 0.1) {
                HStack {
                    Text("Температура")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(temperature, format: .number.precision(.fractionLength(1)))
                        .fontWeight(.semibold)
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
                .disabled(!OpenAIClient.usesMaxCompletionTokens(model: settingsModel))
            }
        }
    }

    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TemplatePanelTitle("Переменные · клик вставляет в промт")
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
            Button("Сбросить к стандартному") { resetToDefault() }
                .foregroundStyle(.secondary)
            Spacer()
            if let savedNote {
                Text(savedNote)
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            Button {
                showSandbox = true
            } label: {
                Label("Песочница", systemImage: "play.fill")
            }
            Button("Сохранить") { save() }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    private func insert(_ token: String) {
        insertionToken = token
        insertionRequestID += 1
    }

    private func load() {
        user = template.userPromptTemplate
        temperature = template.temperature
        maxTokens = template.maxTokens
        reasoningEffort = template.reasoningEffort ?? ""
    }

    private func save() {
        template.userPromptTemplate = user
        template.temperature = temperature
        template.maxTokens = maxTokens
        // Persist only when the model supports it and a level is chosen; otherwise clear it.
        template.reasoningEffort = (OpenAIClient.usesMaxCompletionTokens(model: settingsModel) && !reasoningEffort.isEmpty)
            ? reasoningEffort : nil
        template.templateVersion += 1
        template.updatedAt = .now
        savedNote = "Сохранено · версия \(template.templateVersion)"
    }

    private func sandboxTemplate() -> StageTemplate {
        StageTemplate(
            stage: stage,
            articleType: template.articleTypeRaw.flatMap(ArticleType.init(rawValue:)),
            userPromptTemplate: user,
            modelName: settingsModel,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoningEffort: (OpenAIClient.usesMaxCompletionTokens(model: settingsModel) && !reasoningEffort.isEmpty)
                ? reasoningEffort
                : nil,
            templateVersion: template.templateVersion
        )
    }

    private func resetToDefault() {
        let content = StageTemplateDefaults.content(for: stage)
        user = content.userPromptTemplate
        temperature = content.temperature
        maxTokens = content.maxTokens
        reasoningEffort = ""
        save()
        savedNote = "Сброшено к стандартному"
    }
}

private struct TemplatePanelTitle: View {
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
