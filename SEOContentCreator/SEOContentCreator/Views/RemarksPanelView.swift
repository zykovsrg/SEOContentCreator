import SwiftUI

struct RemarksPanelView: View {
    var remarks: [Remark]
    var acceptedIDs: Set<UUID>
    var rejectedIDs: Set<UUID>
    var unresolvedIDs: Set<UUID> = []
    var appendedIDs: Set<UUID> = []
    var redoingIDs: Set<UUID> = []
    var onAccept: (Remark) -> Void
    var onReject: (Remark) -> Void
    var onSelect: (Remark) -> Void
    var onRedo: (Remark, String) -> Void = { _, _ in }

    @State private var comments: [UUID: String] = [:]

    var body: some View {
        if remarks.isEmpty {
            ContentUnavailableView("Замечаний нет", systemImage: "checkmark.seal")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(remarks) { remark in
                        card(remark)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(remark) }
                    }
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder private func card(_ remark: Remark) -> some View {
        let accepted = acceptedIDs.contains(remark.id)
        let rejected = rejectedIDs.contains(remark.id)
        let unresolved = accepted && unresolvedIDs.contains(remark.id)
        let appended = accepted && appendedIDs.contains(remark.id)
        let redoing = redoingIDs.contains(remark.id)
        VStack(alignment: .leading, spacing: 8) {
            Text(remark.category.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(remark.explanation).font(.callout)
            if !remark.quote.isEmpty {
                Text("было: \(remark.quote)").font(.caption).foregroundStyle(.secondary)
                if remark.suggestion.isEmpty {
                    Text("станет: удалить").font(.caption).foregroundStyle(.red)
                } else {
                    Text("станет: \(remark.suggestion)").font(.caption).foregroundStyle(.green)
                }
            }
            HStack(spacing: 8) {
                Button("Принять") { onAccept(remark) }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(accepted || redoing)
                Button("Отклонить") { onReject(remark) }
                    .buttonStyle(.bordered).tint(.red)
                    .disabled(rejected || redoing)
                Spacer()
                if unresolved {
                    Label("не применено", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else if appended {
                    Label("добавлено в конец", systemImage: "text.append")
                        .font(.caption).foregroundStyle(.orange)
                } else if accepted {
                    Label("принято", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                } else if rejected {
                    Label("отклонено", systemImage: "xmark").font(.caption).foregroundStyle(.secondary)
                }
            }
            if unresolved {
                Text("Не удалось найти эту фразу в тексте, а добавить нечего — правку нужно внести вручную (через «Редактор») или нажать «Переделать», чтобы ИИ уточнил цитату.")
                    .font(.caption2).foregroundStyle(.orange)
            } else if appended {
                Text("Не удалось найти эту фразу в исходном месте, поэтому правка добавлена отдельным блоком в конец текста — при желании перенесите её вручную через «Редактор».")
                    .font(.caption2).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                TextField("Комментарий для ИИ…",
                          text: Binding(get: { comments[remark.id] ?? "" }, set: { comments[remark.id] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .disabled(redoing)
                if redoing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Переделать") {
                        let comment = (comments[remark.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !comment.isEmpty else { return }
                        onRedo(remark, comment)
                    }
                    .disabled((comments[remark.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}
