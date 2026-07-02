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
                if !isStreaming, let rightText {
                    diffParagraphs(ParagraphDiff.oldSide(old: leftText, new: rightText), removedTint: .red)
                        .padding()
                } else {
                    MarkdownBlocksView(text: leftText).padding()
                }
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
                diffParagraphs(ParagraphDiff.newSide(old: leftText, new: rightText), addedTint: .green)
                    .padding()
            }
        } else if let rightText {
            ScrollView {
                MarkdownBlocksView(text: rightText).padding()
            }
        } else {
            ContentUnavailableView("Запустите этап", systemImage: "play.circle")
        }
    }

    /// Renders diffed paragraphs with Markdown formatting, tinting added/removed
    /// paragraphs with the given color (`nil` means no tint for that kind).
    @ViewBuilder
    private func diffParagraphs(_ lines: [ParagraphDiffLine], addedTint: Color? = nil, removedTint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MarkdownBlocksView(text: line.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(tint(for: line.kind, addedTint: addedTint, removedTint: removedTint))
            }
        }
    }

    private func tint(for kind: ParagraphDiffKind, addedTint: Color?, removedTint: Color?) -> Color {
        switch kind {
        case .added:     return addedTint?.opacity(0.18) ?? .clear
        case .removed:   return removedTint?.opacity(0.18) ?? .clear
        case .unchanged: return .clear
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
