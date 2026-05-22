import SwiftUI

struct RemarksPanelView: View {
    var remarks: [Remark]
    var acceptedIDs: Set<UUID>
    var rejectedIDs: Set<UUID>
    var onAccept: (Remark) -> Void
    var onReject: (Remark) -> Void
    var onSelect: (Remark) -> Void

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
            if !remark.suggestion.isEmpty {
                Text("было: \(remark.quote)").font(.callout).foregroundStyle(.secondary)
                Text("станет: \(remark.suggestion)").font(.callout).foregroundStyle(.green)
            }
            HStack {
                Button("Принять") { onAccept(remark) }
                    .controlSize(.regular).buttonStyle(.borderedProminent)
                    .disabled(acceptedIDs.contains(remark.id))
                Button("Отклонить") { onReject(remark) }
                    .controlSize(.regular)
                    .disabled(rejectedIDs.contains(remark.id))
                Spacer()
                if acceptedIDs.contains(remark.id) {
                    Label("принято", systemImage: "checkmark").font(.subheadline).foregroundStyle(.green)
                } else if rejectedIDs.contains(remark.id) {
                    Label("отклонено", systemImage: "xmark").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
