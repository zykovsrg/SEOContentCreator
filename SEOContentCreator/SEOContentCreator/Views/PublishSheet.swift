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

    private var hasPrevious: Bool { !topic.publications.isEmpty }
    private var sortedPublications: [ExternalDocument] {
        topic.publications.sorted(by: { $0.publishedAt > $1.publishedAt })
    }
    private var overwriteTargetID: String? {
        selectedDocID ?? sortedPublications.first?.docID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Публикация в Google Docs").font(.title2).bold()

            GroupBox("Что публикуется") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Документ: \(topic.title)")
                    Text("Папка Google Drive: SEO-статьи клиники").foregroundStyle(.secondary)
                    if topic.currentVersion == nil {
                        Text("Нет принятой версии текста.").foregroundStyle(.red)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(20)
        .frame(width: 520, height: 460)
        .confirmationDialog("Перезаписать существующий документ?", isPresented: $confirmOverwrite) {
            Button("Перезаписать", role: .destructive) { Task { await doPublish() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Текущее содержимое документа будет заменено.")
        }
    }

    private func doPublish() async {
        await publisher.publish(
            topic: topic,
            mode: mode,
            targetDocID: mode == .overwrite ? overwriteTargetID : nil,
            in: context
        )
        if publisher.lastErrorMessage == nil { dismiss() }
    }
}
