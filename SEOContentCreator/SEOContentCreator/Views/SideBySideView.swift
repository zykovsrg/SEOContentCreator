import SwiftUI

struct SideBySideView: View {
    var leftText: String?
    var rightText: String?
    var isStreaming: Bool
    /// True while running a checking stage (SEO/факт/финальная вычитка) — those
    /// stream raw JSON remarks, not article text, so the right column shows a
    /// status indicator instead of the raw stream.
    var isCheckingStage: Bool = false
    /// True once a checking stage finished with zero remarks — shows an explicit
    /// "no remarks" confirmation instead of the empty "start the stage" placeholder.
    var checkedWithNoRemarks: Bool = false

    private static let streamBottomID = "streamBottom"

    var body: some View {
        HStack(spacing: 0) {
            column(title: "Текущая версия", content: leftColumn)
            Divider()
            column(title: rightTitle, content: rightColumn)
        }
    }

    private var rightTitle: String {
        if isStreaming { return isCheckingStage ? "Идёт проверка…" : "Генерация…" }
        return "Новая версия"
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
        if isStreaming && isCheckingStage {
            ContentUnavailableView {
                Label("Идёт проверка…", systemImage: "hourglass")
            } description: {
                ProgressView()
            }
        } else if isStreaming {
            // During generation show only the tail of the growing text (see `streamingTail`),
            // auto-scrolling to keep the newest output visible. The full formatted diff is
            // shown once generation finishes.
            ScrollViewReader { proxy in
                ScrollView {
                    Text((rightText ?? "").streamingTail())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    Color.clear.frame(height: 1).id(Self.streamBottomID)
                }
                .onChange(of: rightText) { _, _ in
                    proxy.scrollTo(Self.streamBottomID, anchor: .bottom)
                }
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
        } else if checkedWithNoRemarks {
            ContentUnavailableView("Проверка пройдена, замечаний нет", systemImage: "checkmark.circle")
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

extension String {
    /// The last portion of a growing stream, for cheap live display. SwiftUI `Text` lays out
    /// its entire string on every update and does not virtualize, so rendering the full,
    /// ever-growing stream re-lays-out a larger and larger string and lags badly on long
    /// output. While generation is in flight only the newest text matters; the complete text
    /// (and the formatted diff) is shown once it finishes.
    func streamingTail(maxChars: Int = 4000) -> String {
        guard count > maxChars else { return self }
        let tail = suffix(maxChars)
        if let newline = tail.firstIndex(of: "\n") {
            return "…\n" + tail[tail.index(after: newline)...]
        }
        return "…" + tail
    }
}
