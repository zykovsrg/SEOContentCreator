import SwiftUI
import SwiftData

struct PublishSheet: View {
    let topic: Topic
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var publisher = ArticlePublisher.live(auth: GoogleAuthService())
    @State private var mode: PublishMode = .newDocument
    @State private var confirmOverwrite = false
    @State private var selectedDocID: String?
    @State private var selectedImageIDs: Set<UUID> = []
    @State private var copiedLink: String?

    private var hasPrevious: Bool { !topic.publications.isEmpty }
    private var sortedPublications: [ExternalDocument] {
        topic.publications.sorted(by: { $0.publishedAt > $1.publishedAt })
    }
    private var overwriteTargetID: String? {
        selectedDocID ?? sortedPublications.first?.docID
    }
    private var selectableImages: [GeneratedImage] {
        topic.images.filter { !$0.isArchived }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Group {
            if publisher.lastPublishedDocURL != nil { resultView } else { formView }
        }
        .padding(20)
        .frame(width: 520, height: 600)
        .confirmationDialog("Перезаписать существующий документ?", isPresented: $confirmOverwrite) {
            Button("Перезаписать", role: .destructive) { Task { await doPublish() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Текущее содержимое документа будет заменено.")
        }
        .onAppear {
            if let coverID = topic.coverImageID,
               selectableImages.contains(where: { $0.uuid == coverID }) {
                selectedImageIDs = [coverID]
            }
        }
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Публикация в Google Docs").font(.title2).bold()

            GroupBox("Что публикуется") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Документ: \(topic.title)")
                    Text("Папка Google Drive: SEO-статьи клиники").foregroundStyle(.secondary)
                    if let link = topic.illustrationsFolderURL, let url = URL(string: link) {
                        Link("Папка иллюстраций на Диске", destination: url).font(.callout)
                    }
                    Text("После публикации документ и папка с картинками получат доступ по ссылке.")
                        .font(.caption).foregroundStyle(.secondary)
                    if topic.currentVersion == nil {
                        Text("Нет принятой версии текста.").foregroundStyle(.red)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            if !selectableImages.isEmpty {
                GroupBox("Картинки на Google Диск") {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                            ForEach(selectableImages, id: \.uuid) { image in
                                imageCell(image)
                            }
                        }
                    }
                    .frame(height: 120)
                }
            }

            if hasPrevious {
                Picker("Режим", selection: $mode) {
                    Text("Создать новый документ").tag(PublishMode.newDocument)
                    Text("Перезаписать существующий").tag(PublishMode.overwrite)
                }.pickerStyle(.radioGroup)
            }

            if mode == .overwrite && !sortedPublications.isEmpty {
                Picker("Документ для перезаписи", selection: Binding(
                    get: { overwriteTargetID },
                    set: { selectedDocID = $0 }
                )) {
                    ForEach(sortedPublications, id: \.docID) { doc in
                        Text(doc.docURL).tag(Optional(doc.docID))
                    }
                }
            }

            if let error = publisher.lastErrorMessage {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            if !topic.publications.isEmpty {
                GroupBox("История публикаций") {
                    ForEach(sortedPublications, id: \.uuid) { doc in
                        HStack {
                            Link(doc.docURL, destination: URL(string: doc.docURL)!).lineLimit(1)
                            Spacer()
                            Text(doc.publishedAt, style: .date).foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }
                Button(publisher.isPublishing ? "Публикую…" : "Опубликовать") {
                    if mode == .overwrite { confirmOverwrite = true } else { Task { await doPublish() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(publisher.isPublishing || topic.currentVersion == nil)
            }
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Статья опубликована", systemImage: "checkmark.circle.fill")
                .font(.title2).bold().foregroundStyle(.green)

            if let warning = publisher.lastErrorMessage {
                Text(warning).foregroundStyle(.orange).font(.callout)
            }

            GroupBox("Ссылки") {
                VStack(alignment: .leading, spacing: 12) {
                    linkRow(title: "Документ статьи", urlString: publisher.lastPublishedDocURL,
                            emptyNote: nil)
                    linkRow(title: "Папка с иллюстрациями", urlString: topic.illustrationsFolderURL,
                            emptyNote: "Картинки не загружались, поэтому папки нет.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Доступ по ссылке открыт: контент-менеджер сможет открыть документ и забрать фотки без приглашения и без входа в Google.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private func linkRow(title: String, urlString: String?, emptyNote: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout).bold()
            if let urlString, let url = URL(string: urlString) {
                HStack(spacing: 8) {
                    Link(urlString, destination: url)
                        .lineLimit(1).truncationMode(.middle)
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(urlString, forType: .string)
                        copiedLink = title
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Скопировать ссылку")
                    if copiedLink == title {
                        Text("Скопировано").font(.caption).foregroundStyle(.green)
                    }
                }
            } else if let emptyNote {
                Text(emptyNote).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func imageCell(_ image: GeneratedImage) -> some View {
        let isSelected = selectedImageIDs.contains(image.uuid)
        Button {
            if isSelected { selectedImageIDs.remove(image.uuid) }
            else { selectedImageIDs.insert(image.uuid) }
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    if let nsImage = NSImage(data: image.data) {
                        Image(nsImage: nsImage)
                            .resizable().scaledToFill()
                            .frame(width: 80, height: 60).clipped()
                            .cornerRadius(6)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary).frame(width: 80, height: 60)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(2)
                }
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                Text(image.driveFileID != nil ? "на Диске" : image.role.title)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func doPublish() async {
        let images = selectableImages.filter { selectedImageIDs.contains($0.uuid) }
        await publisher.publish(
            topic: topic,
            mode: mode,
            targetDocID: mode == .overwrite ? overwriteTargetID : nil,
            imagesToUpload: images,
            in: context
        )
    }
}
