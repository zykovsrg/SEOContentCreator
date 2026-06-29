import SwiftUI

struct ImagePromptEditorView: View {
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
