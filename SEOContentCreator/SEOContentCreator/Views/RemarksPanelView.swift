import SwiftUI

struct RemarksPanelView: View {
    var remarks: [Remark]
    var acceptedIDs: Set<UUID>
    var rejectedIDs: Set<UUID>
    var redoingIDs: Set<UUID> = []
    var onAccept: (Remark) -> Void
    var onReject: (Remark) -> Void
    var onSelect: (Remark) -> Void
    var onRedo: (Remark, String) -> Void = { _, _ in }

    @State private var comments: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Замечания: \(remarks.count)").font(.headline).foregroundStyle(.secondary).padding(8)
            Divider()
            if remarks.isEmpty {
                ContentUnavailableView("Замечаний нет", systemImage: "checkmark.seal")
            } else {
                List(remarks) { remark in
                    card(remark)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(remark) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private func card(_ remark: Remark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(remark.category).font(.headline).foregroundStyle(.blue)
            Text(remark.explanation).font(.body)
            if !remark.quote.isEmpty {
                Text("было: \(remark.quote)").font(.callout).foregroundStyle(.secondary)
                if remark.suggestion.isEmpty {
                    Text("станет: Удалить").font(.callout).foregroundStyle(.red)
                } else {
                    Text("станет: \(remark.suggestion)").font(.callout).foregroundStyle(.green)
                }
            }
            HStack {
                Button("Принять") { onAccept(remark) }
                    .controlSize(.regular).buttonStyle(.borderedProminent)
                    .disabled(acceptedIDs.contains(remark.id) || redoingIDs.contains(remark.id))
                Button("Отклонить") { onReject(remark) }
                    .controlSize(.regular)
                    .disabled(rejectedIDs.contains(remark.id) || redoingIDs.contains(remark.id))
                Spacer()
                if acceptedIDs.contains(remark.id) {
                    Label("принято", systemImage: "checkmark").font(.subheadline).foregroundStyle(.green)
                } else if rejectedIDs.contains(remark.id) {
                    Label("отклонено", systemImage: "xmark").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                TextField("Комментарий для ИИ, чтобы доработать правку…",
                          text: Binding(get: { comments[remark.id] ?? "" }, set: { comments[remark.id] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .disabled(redoingIDs.contains(remark.id))
                if redoingIDs.contains(remark.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Доработать") {
                        let comment = (comments[remark.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !comment.isEmpty else { return }
                        onRedo(remark, comment)
                    }
                    .disabled((comments[remark.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
