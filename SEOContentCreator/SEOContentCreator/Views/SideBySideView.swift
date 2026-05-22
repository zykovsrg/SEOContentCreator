import SwiftUI

struct SideBySideView: View {
    var leftText: String?
    var rightText: String?
    var isStreaming: Bool

    var body: some View {
        HStack(spacing: 0) {
            column(title: "Текущая версия", content: leftColumn)
            Divider()
            column(title: isStreaming ? "Генерация…" : "Новая версия", content: rightColumn)
        }
    }

    @ViewBuilder private var leftColumn: some View {
        if let leftText, !leftText.isEmpty {
            ScrollView {
                Text(leftText).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
        } else {
            ContentUnavailableView("Нет текущей версии", systemImage: "doc")
        }
    }

    @ViewBuilder private var rightColumn: some View {
        if isStreaming {
            ScrollView {
                Text(rightText ?? "").frame(maxWidth: .infinity, alignment: .leading).padding()
            }
        } else if let rightText, let leftText {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(ParagraphDiff.newSide(old: leftText, new: rightText).enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(line.kind == .added ? Color.green.opacity(0.18) : Color.clear)
                    }
                }.padding()
            }
        } else if let rightText {
            ScrollView {
                Text(rightText).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
        } else {
            ContentUnavailableView("Запустите этап", systemImage: "play.circle")
        }
    }

    private func column<C: View>(title: String, content: C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary).padding(6)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
