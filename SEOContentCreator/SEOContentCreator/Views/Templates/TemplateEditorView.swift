import SwiftUI

struct TemplateEditorView: View {
    @Bindable var template: StageTemplate
    @AppStorage("openAIModel") private var settingsModel = "gpt-4.1"

    @State private var user = ""
    @State private var temperature = 0.6
    @State private var maxTokens = 8000
    /// Empty string = "по умолчанию" (nil, parameter omitted).
    @State private var reasoningEffort = ""
    @State private var showVariables = false
    @State private var savedNote: String?
    @State private var showSandbox = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(template.stage?.title ?? template.stageRaw).font(.title2).bold()
                Text("Версия шаблона: \(template.templateVersion)")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Пользовательский промт (инструкция с переменными)").font(.headline)
                Text("Роль, общие правила и редполитика берутся из разделов «ИИ-роли» и «Редполитика и источники» и добавляются автоматически.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $user).frame(minHeight: 200).border(.gray.opacity(0.3))

                Text("Параметры генерации").font(.headline)
                Text("Модель: \(settingsModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Температура: \(temperature, specifier: "%.1f")",
                        value: $temperature, in: 0...1, step: 0.1)
                    .frame(maxWidth: 360, alignment: .leading)
                Stepper("Max tokens: \(maxTokens)", value: $maxTokens, in: 1000...32000, step: 1000)
                    .frame(maxWidth: 360, alignment: .leading)

                if OpenAIClient.usesMaxCompletionTokens(model: settingsModel) {
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
                    Button("Песочница") { showSandbox = true }
                    Button("Сбросить к стандартному") { resetToDefault() }
                    Spacer()
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showSandbox) {
            TemplateSandboxSheet(
                stage: template.stage ?? .draft,
                template: sandboxTemplate()
            )
        }
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
        savedNote = "Сохранено (версия \(template.templateVersion))"
    }

    private func sandboxTemplate() -> StageTemplate {
        StageTemplate(
            stage: template.stage ?? .draft,
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
        let c = StageTemplateDefaults.content(for: template.stage ?? .draft)
        user = c.userPromptTemplate
        temperature = c.temperature
        maxTokens = c.maxTokens
        reasoningEffort = ""
        save()
        savedNote = "Сброшено к стандартному"
    }
}
