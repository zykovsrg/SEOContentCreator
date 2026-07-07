import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ImagesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic

    @State private var activeSheet: SheetKind?

    private enum SheetKind: Identifiable {
        case create(ImageRole)
        case refine(GeneratedImage)

        var id: String {
            switch self {
            case .create(let role): return "create-\(role.rawValue)"
            case .refine(let image): return "refine-\(image.uuid.uuidString)"
            }
        }
    }

    private var images: [GeneratedImage] {
        topic.images.filter { !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
    }

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Изображения").font(.headline)
                Spacer()
                Button { activeSheet = .create(.cover) } label: {
                    Label("Сгенерировать обложку", systemImage: "photo")
                }
                Button { activeSheet = .create(.illustration) } label: {
                    Label("Сгенерировать иллюстрацию", systemImage: "photo.badge.plus")
                }
            }

            if images.isEmpty {
                ContentUnavailableView("Пока нет изображений", systemImage: "photo.on.rectangle",
                                       description: Text("Сгенерируйте обложку или иллюстрацию."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(images) { image in
                            cell(image)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 720, height: 620)
        .sheet(item: $activeSheet) { kind in
            switch kind {
            case .create(let role):
                ImageGenerationSheet(topic: topic, mode: .create(role: role))
            case .refine(let image):
                ImageGenerationSheet(topic: topic, mode: .refine(source: image))
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    @ViewBuilder
    private func cell(_ image: GeneratedImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let nsImage = NSImage(data: image.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.08))
                    .border(.gray.opacity(0.3))
            }
            HStack(spacing: 6) {
                Text(image.role.title).font(.caption).bold()
                if topic.coverImageID == image.uuid {
                    Text("текущая").font(.caption2).foregroundStyle(.green)
                }
                if image.sourceImageID != nil {
                    Text("доработка").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let anchor = image.anchorQuote, !anchor.isEmpty {
                Text(anchor).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Button("Файл") { export(image) }
                Button("Доработать") { activeSheet = .refine(image) }
                if image.role == .cover {
                    Button("Обложка") { topic.coverImageID = image.uuid }
                        .disabled(topic.coverImageID == image.uuid)
                }
                Button("Архив", role: .destructive) { archive(image) }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
    }

    @State private var exportError: String?

    private func export(_ image: GeneratedImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = "\(image.role.rawValue)-\(image.uuid.uuidString.prefix(8)).png"
        let data = image.data
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                exportError = "Не удалось сохранить файл: \(error.localizedDescription)"
            }
        }
        // Внутри SwiftUI-sheet системное окно сохранения нужно показывать как
        // sheet текущего окна: старый `runModal()` изнутри sheet на macOS часто
        // не отображается вовсе.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private func archive(_ image: GeneratedImage) {
        image.isArchived = true
        if topic.coverImageID == image.uuid { topic.coverImageID = nil }
    }
}
