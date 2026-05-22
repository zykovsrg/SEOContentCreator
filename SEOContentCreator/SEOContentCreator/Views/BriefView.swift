import SwiftUI
import SwiftData

struct BriefView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Existing topic to edit, or nil to create a new one.
    var topic: Topic?

    @State private var title = ""
    @State private var articleType: ArticleType = .disease
    @State private var direction = ""
    @State private var doctor = ""
    @State private var volume = ""
    @State private var useStyle = false
    @State private var notes = ""

    var body: some View {
        Form {
            TextField("Название *", text: $title)
            Picker("Тип статьи *", selection: $articleType) {
                ForEach(ArticleType.allCases) { Text($0.title).tag($0) }
            }
            TextField("Направление", text: $direction)
            TextField("Врач", text: $doctor)
            TextField("Целевой объём (знаков)", text: $volume)
            Toggle("Использовать Стиль/Главред", isOn: $useStyle)
            TextField("Заметки", text: $notes, axis: .vertical).lineLimit(3...6)
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
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
