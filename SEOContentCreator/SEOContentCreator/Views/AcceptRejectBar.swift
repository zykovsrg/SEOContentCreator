import SwiftUI

struct AcceptRejectBar: View {
    var canAct: Bool
    var onAcceptAll: () -> Void
    var onAcceptPartial: () -> Void
    var onReject: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Отклонить", role: .destructive, action: onReject).disabled(!canAct)
            Button("Принять частично", action: onAcceptPartial).disabled(!canAct)
            Button("Принять всё", action: onAcceptAll).keyboardShortcut(.defaultAction).disabled(!canAct)
        }
        .padding(8)
    }
}

struct PartialAcceptSheet: View {
    @Environment(\.dismiss) private var dismiss
    var oldText: String
    var newText: String
    var onApply: (Set<Int>) -> Void

    @State private var accepted: Set<Int> = []

    private var newParagraphs: [String] { ParagraphDiff.paragraphs(newText) }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Выберите абзацы из новой версии").font(.headline).padding(.bottom, 4)
            List {
                ForEach(Array(newParagraphs.enumerated()), id: \.offset) { index, para in
                    Toggle(isOn: Binding(
                        get: { accepted.contains(index) },
                        set: { if $0 { accepted.insert(index) } else { accepted.remove(index) } }
                    )) {
                        Text(para).lineLimit(3)
                    }
                }
            }
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Применить") { onApply(accepted); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560, height: 480)
    }
}
