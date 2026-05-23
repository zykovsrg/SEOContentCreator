import SwiftUI
import SwiftData

struct TemplatesView: View {
    @Query private var templates: [StageTemplate]
    @State private var selectedID: UUID?

    private var sortedTemplates: [StageTemplate] {
        templates.sorted { lhs, rhs in
            order(lhs.stageRaw) < order(rhs.stageRaw)
        }
    }

    private func order(_ raw: String) -> Int {
        PipelineStage.allCases.firstIndex { $0.rawValue == raw } ?? Int.max
    }

    private var selectedTemplate: StageTemplate? {
        templates.first { $0.uuid == selectedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                Section("Промты этапов") {
                    ForEach(sortedTemplates) { t in
                        Text(t.stage?.title ?? t.stageRaw).tag(t.uuid)
                    }
                }
            }
            .frame(width: 240)
            Divider()
            if let t = selectedTemplate {
                TemplateEditorView(template: t).id(t.uuid)
            } else {
                ContentUnavailableView("Выберите этап", systemImage: "doc.text")
            }
        }
        .navigationTitle("Шаблоны")
        .onAppear { if selectedID == nil { selectedID = sortedTemplates.first?.uuid } }
    }
}

private struct TemplateEditorView: View {
    @Bindable var template: StageTemplate

    @State private var system = ""
    @State private var user = ""
    @State private var model = "gpt-4.1"
    @State private var temperature = 0.6
    @State private var maxTokens = 8000
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

                Text("Системный промт (роль, правила, методичка)").font(.headline)
                TextEditor(text: $system).frame(minHeight: 160).border(.gray.opacity(0.3))

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
    }

    private func save() {
        template.systemPrompt = system
        template.userPromptTemplate = user
        template.modelName = model
        template.temperature = temperature
        template.maxTokens = maxTokens
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
        save()
        savedNote = "Сброшено к стандартному"
    }
}
