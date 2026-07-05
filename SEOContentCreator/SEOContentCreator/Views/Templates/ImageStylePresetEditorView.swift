import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImageStylePresetEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var preset: ImageStylePreset
    var onDelete: () -> Void

    @State private var name = ""
    @State private var styleText = ""
    @State private var size = "1024x1024"
    @State private var quality = "high"
    @State private var savedNote: String?

    private let sizes = ["1024x1024", "1536x1024", "1024x1536"]
    private let qualities = ["high", "medium", "low"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Пресет стиля").font(.title2).bold()

                TextField("Имя", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Text("Описание стиля (палитра, ограничения, аудитория)").font(.headline)
                TextEditor(text: $styleText).frame(minHeight: 200).border(.gray.opacity(0.3))

                Picker("Размер", selection: $size) {
                    ForEach(sizes, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 280, alignment: .leading)
                Picker("Качество", selection: $quality) {
                    ForEach(qualities, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 280, alignment: .leading)

                HStack(spacing: 8) {
                    Text("Референс-картинка:")
                    if preset.referenceImageData != nil {
                        Text("есть").foregroundStyle(.green)
                        Button("Удалить референс") { preset.referenceImageData = nil }
                    } else {
                        Text("нет").foregroundStyle(.secondary)
                    }
                    Button("Выбрать…") { pickReference() }
                }
                .font(.callout)

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    if matchingDefault != nil {
                        Button("Сбросить к стандартному") { resetToDefault() }
                    }
                    Spacer()
                    Button("Удалить пресет", role: .destructive) { deletePreset() }
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private var matchingDefault: ImageStylePresetDefault? {
        ImageStylePresetDefaults.matching(name: preset.name)
    }

    private func load() {
        name = preset.name
        styleText = preset.styleText
        size = preset.size
        quality = preset.quality
    }

    private func save() {
        preset.name = name
        preset.styleText = styleText
        preset.size = size
        preset.quality = quality
        preset.updatedAt = .now
        savedNote = "Сохранено"
    }

    private func resetToDefault() {
        guard let def = matchingDefault else { return }
        styleText = def.styleText
        name = def.name
        size = def.size
        save()
        savedNote = "Сброшено к стандартному"
    }

    private func deletePreset() {
        context.delete(preset)
        onDelete()
    }

    private func pickReference() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            preset.referenceImageData = data
        }
    }
}
