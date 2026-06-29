import SwiftUI

struct EditorDictionaryEditorView: View {
    @Bindable var dictionary: EditorDictionary

    @State private var clichesText = ""
    @State private var longLimit = EditorDictionaryDefaults.longSentenceWordLimit
    @State private var window = EditorDictionaryDefaults.repeatWindowWords
    @State private var savedNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Словарь правок").font(.title2).bold()
                Text("Версия: \(dictionary.version)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Используется в окне «Подсказки». Только грубая алгоритмическая проверка, без ИИ.")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Штампы (по одному на строку)").font(.headline)
                TextEditor(text: $clichesText).frame(minHeight: 220).border(.gray.opacity(0.3))

                Text("Пороги").font(.headline)
                Stepper("Длинное предложение: от \(longLimit) слов",
                        value: $longLimit, in: 10...80, step: 1)
                    .frame(maxWidth: 360, alignment: .leading)
                Stepper("Окно повторов: \(window) слов",
                        value: $window, in: 5...80, step: 1)
                    .frame(maxWidth: 360, alignment: .leading)

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
        clichesText = dictionary.clichesText
        longLimit = dictionary.longSentenceWordLimit
        window = dictionary.repeatWindowWords
    }

    private func save() {
        dictionary.clichesText = clichesText
        dictionary.longSentenceWordLimit = longLimit
        dictionary.repeatWindowWords = window
        dictionary.version += 1
        dictionary.updatedAt = .now
        savedNote = "Сохранено (версия \(dictionary.version))"
    }

    private func resetToDefault() {
        clichesText = EditorDictionaryDefaults.clichesText
        longLimit = EditorDictionaryDefaults.longSentenceWordLimit
        window = EditorDictionaryDefaults.repeatWindowWords
        save()
        savedNote = "Сброшено к стандартному"
    }
}
