import SwiftUI
import SwiftData
import AppKit

struct ImageGenerationSheet: View {
    enum Mode {
        case create(role: ImageRole)
        case refine(source: GeneratedImage)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    let mode: Mode

    @AppStorage("imageModel") private var imageModel = "gpt-image-1"
    @Query private var presets: [ImageStylePreset]
    @Query private var promptTemplates: [ImagePromptTemplate]

    @State private var subject = ""
    @State private var fragment = ""
    @State private var selectedPresetID: UUID?
    @State private var generator: ImageGenerator?
    @State private var lastComposedPrompt = ""

    private var isRunning: Bool { generator?.isRunning ?? false }
    private var isRefine: Bool { if case .refine = mode { return true } else { return false } }
    private var isIllustration: Bool {
        switch mode {
        case .create(let role): return role == .illustration
        case .refine(let source): return source.role == .illustration
        }
    }
    private var selectedPreset: ImageStylePreset? {
        presets.first { $0.uuid == selectedPresetID } ?? presets.first
    }
    private var titleText: String {
        switch mode {
        case .create(let role): return role == .cover ? "Генерация обложки" : "Генерация иллюстрации"
        case .refine: return "Доработка изображения"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleText).font(.headline)

            if case .refine(let source) = mode, let image = nsImage(source.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 120)
                    .border(.gray.opacity(0.3))
            }

            if isIllustration && !isRefine {
                Text("Фрагмент для иллюстрации (вставьте нужный кусок текста)")
                    .font(.subheadline)
                TextEditor(text: $fragment)
                    .frame(minHeight: 70)
                    .border(.gray.opacity(0.3))
            }

            Text(isRefine ? "Что изменить" : "Промт (сюжет)").font(.subheadline)
            TextEditor(text: $subject)
                .frame(minHeight: 110)
                .border(.gray.opacity(0.3))

            Picker("Пресет стиля", selection: $selectedPresetID) {
                ForEach(presets) { preset in
                    Text(preset.name).tag(Optional(preset.uuid))
                }
            }
            .frame(maxWidth: 360, alignment: .leading)

            if let error = generator?.lastErrorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            if let data = generator?.previewData, let image = nsImage(data) {
                ScrollView {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(4)
                }
                .frame(minHeight: 220)
                .border(.gray.opacity(0.3))
            }

            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button(isRunning ? "Генерация…" : "Сгенерировать") { run() }
                    .disabled(isRunning || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if generator?.previewData != nil {
                    Button("Сохранить в галерею") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isRunning)
                }
            }
        }
        .padding()
        .frame(width: 640, height: 660)
        .onAppear(perform: setup)
    }

    private func setup() {
        if generator == nil { generator = .live(model: imageModel) }
        if selectedPresetID == nil { selectedPresetID = presets.first?.uuid }
        guard case .create(let role) = mode else { return }
        let kind: ImagePromptKind = role == .cover ? .cover : .illustration
        guard let template = promptTemplates.first(where: { $0.kindRaw == kind.rawValue }) else { return }
        let placeholder = role == .illustration ? "{{выделенный_фрагмент}}" : ""
        subject = ImagePromptBuilder().subject(template: template, topic: topic, fragment: placeholder)
    }

    private func run() {
        guard let generator else { return }
        let preset = selectedPreset
        let composed: String
        var references: [Data] = []

        switch mode {
        case .create:
            let filled = subject.replacingOccurrences(of: "{{выделенный_фрагмент}}", with: fragment)
            composed = ImagePromptBuilder().compose(subject: filled, preset: preset)
            if let ref = preset?.referenceImageData { references = [ref] }
        case .refine(let source):
            composed = ImagePromptBuilder().compose(subject: subject, preset: preset)
            references = [source.data]
            if let ref = preset?.referenceImageData { references.append(ref) }
        }

        lastComposedPrompt = composed
        let size = preset?.size ?? "1024x1024"
        let quality = preset?.quality ?? "high"
        Task {
            await generator.render(topic: topic, prompt: composed, size: size, quality: quality,
                                   references: references, in: context)
        }
    }

    private func save() {
        guard let generator, let data = generator.previewData else { return }
        let preset = selectedPreset
        switch mode {
        case .create(let role):
            ImageSaver.saveGenerated(
                data: data, role: role, prompt: lastComposedPrompt,
                fragment: role == .illustration ? fragment : nil,
                preset: preset, model: generator.model, topic: topic, in: context
            )
        case .refine(let source):
            ImageSaver.saveRefined(
                data: data, source: source, prompt: lastComposedPrompt,
                preset: preset, model: generator.model, topic: topic, in: context
            )
        }
        dismiss()
    }

    private func nsImage(_ data: Data) -> NSImage? { NSImage(data: data) }
}
