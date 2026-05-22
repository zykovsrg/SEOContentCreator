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
            Text("Замечания: \(remarks.count)").font(.caption).foregroundStyle(.secondary).padding(6)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(remark.category).font(.caption).bold().foregroundStyle(.blue)
            Text(remark.explanation).font(.subheadline)
            if !remark.suggestion.isEmpty {
                Text("было: \(remark.quote)").font(.caption).foregroundStyle(.secondary)
                Text("станет: \(remark.suggestion)").font(.caption).foregroundStyle(.green)
            }
            HStack {
                Button("Принять") { onAccept(remark) }
                    .controlSize(.small).buttonStyle(.borderedProminent)
                    .disabled(acceptedIDs.contains(remark.id))
                Button("Отклонить") { onReject(remark) }
                    .controlSize(.small)
                    .disabled(rejectedIDs.contains(remark.id))
                Spacer()
                if acceptedIDs.contains(remark.id) {
                    Label("принято", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                } else if rejectedIDs.contains(remark.id) {
                    Label("отклонено", systemImage: "xmark").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
