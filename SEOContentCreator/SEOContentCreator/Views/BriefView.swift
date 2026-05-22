import SwiftUI
import SwiftData

struct BriefView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<KnowledgeNode> { $0.nodeTypeRaw == "direction" },
           sort: \KnowledgeNode.title)
    private var directions: [KnowledgeNode]
    @Query(filter: #Predicate<KnowledgeNode> { $0.nodeTypeRaw == "doctor" },
           sort: \KnowledgeNode.title)
    private var doctors: [KnowledgeNode]

    var topic: Topic?

    @State private var title = ""
    @State private var articleType: ArticleType = .disease
    @State private var direction: KnowledgeNode?
    @State private var doctor: KnowledgeNode?
    @State private var volume = ""
    @State private var useStyle = false
    @State private var notes = ""

    var body: some View {
        Form {
            TextField("Название *", text: $title)
            Picker("Тип статьи *", selection: $articleType) {
                ForEach(ArticleType.allCases) { Text($0.title).tag($0) }
            }
            Picker("Направление *", selection: $direction) {
                Text("Не выбрано").tag(KnowledgeNode?.none)
                ForEach(directions) { Text($0.title).tag(KnowledgeNode?.some($0)) }
            }
            Picker("Врач", selection: $doctor) {
                Text("Не выбран").tag(KnowledgeNode?.none)
                ForEach(doctors) { Text($0.title).tag(KnowledgeNode?.some($0)) }
            }
            TextField("Целевой объём (знаков)", text: $volume)
            Toggle("Использовать Стиль/Главред", isOn: $useStyle)
            TextField("Заметки", text: $notes, axis: .vertical).lineLimit(3...6)
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }
                    .disabled(!BriefValidation.canCreate(title: title))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let topic else { return }
        title = topic.title
        articleType = topic.articleType
        direction = topic.direction
        doctor = topic.doctor
        volume = topic.targetVolume.map(String.init) ?? ""
        useStyle = topic.useStyle
        notes = topic.notes
    }

    private func save() {
        let vol = Int(volume.trimmingCharacters(in: .whitespaces))
        if let topic {
            topic.title = title
            topic.articleType = articleType
            topic.direction = direction
            topic.doctor = doctor
            topic.targetVolume = vol
            topic.useStyle = useStyle
            topic.notes = notes
            topic.updatedAt = .now
        } else {
            let new = Topic(
                title: title, articleType: articleType, targetVolume: vol,
                direction: direction, doctor: doctor, notes: notes, useStyle: useStyle
            )
            context.insert(new)
        }
        dismiss()
    }
}
