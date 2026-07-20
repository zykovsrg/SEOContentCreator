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
    @State private var externalID = ""
    @State private var articleType: ArticleType = .disease
    @State private var direction: KnowledgeNode?
    @State private var doctor: KnowledgeNode?
    @State private var volume = ""
    @State private var notes = ""
    @State private var additionalDirections: [KnowledgeNode] = []
    @State private var newDirectionTitle = ""

    var body: some View {
        Form {
            TextField("Название *", text: $title)
            TextField("ID темы (из таблицы)", text: $externalID)
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
            Section("Дополнительные направления") {
                ForEach(directions) { node in
                    if node !== direction {
                        Toggle(node.title, isOn: Binding(
                            get: { additionalDirections.contains(where: { $0 === node }) },
                            set: { isOn in
                                if isOn { additionalDirections.append(node) }
                                else { additionalDirections.removeAll { $0 === node } }
                            }
                        ))
                    }
                }
                HStack {
                    TextField("Новое направление", text: $newDirectionTitle)
                    Button("Создать") { createDirection() }
                        .disabled(newDirectionTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            TextField("Целевой объём (знаков)", text: $volume)
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
        externalID = topic.externalID
        articleType = topic.articleType
        direction = topic.direction
        doctor = topic.doctor
        volume = topic.targetVolume.map(String.init) ?? ""
        notes = topic.notes
        additionalDirections = topic.additionalDirections
    }

    private func createDirection() {
        let title = newDirectionTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let node = KnowledgeNode(title: title, type: .direction)
        context.insert(node)
        additionalDirections.append(node)
        newDirectionTitle = ""
    }

    private func save() {
        let vol = Int(volume.trimmingCharacters(in: .whitespaces))
        if let topic {
            topic.title = title
            topic.externalID = externalID.trimmingCharacters(in: .whitespaces)
            topic.articleType = articleType
            topic.direction = direction
            topic.doctor = doctor
            topic.targetVolume = vol
            topic.notes = notes
            topic.additionalDirections = additionalDirections.filter { $0 !== direction }
            topic.updatedAt = .now
        } else {
            let new = Topic(
                title: title, articleType: articleType,
                externalID: externalID.trimmingCharacters(in: .whitespaces),
                targetVolume: vol,
                direction: direction, doctor: doctor, notes: notes
            )
            context.insert(new)
            new.additionalDirections = additionalDirections.filter { $0 !== direction }
        }
        dismiss()
    }
}
