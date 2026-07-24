import SwiftUI

struct SideBySideView: View {
    var leftText: String?
    var rightText: String?
    var isStreaming: Bool

    private static let streamBottomID = "streamBottom"

    var body: some View {
        HStack(spacing: 0) {
            column(title: "Текущая версия", content: leftColumn)
            Divider()
            column(title: rightTitle, content: rightColumn)
        }
    }

    private var rightTitle: String {
        if isStreaming { return "Генерация…" }
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
        if isStreaming {
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
            ColumnTitle(title)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single full-width column showing one version of the article text, used
/// when there is nothing to compare against (see `TopicWorkspaceView.isComparing`).
/// Constrains the reading width so long articles stay comfortable to read at
/// full window width, and can show a compact status banner instead of the
/// second, otherwise-empty comparison column.
struct SingleVersionView: View {
    enum Banner {
        case checking
        case checkedNoRemarks
    }

    var title: String
    var text: String?
    var banner: Banner?
    /// Hidden when the workspace draws its own "Текущая версия" header bar.
    var showsTitle: Bool = true

    private let readingWidth: CGFloat = 760

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                ColumnTitle(title)
                Divider()
            }
            if let banner {
                bannerView(banner)
                Divider()
            }
            if let text, !text.isEmpty {
                ScrollView {
                    MarkdownBlocksView(text: text)
                        .frame(maxWidth: readingWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                }
            } else {
                ContentUnavailableView("Нет текущей версии", systemImage: "doc")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func bannerView(_ banner: Banner) -> some View {
        switch banner {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Идёт проверка…").font(.callout)
                Spacer()
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
        case .checkedNoRemarks:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Проверка пройдена, замечаний нет").font(.callout)
                Spacer()
            }
            .padding(8)
            .background(Color.green.opacity(0.1))
        }
    }
}

/// Shared column header style, made a bit more prominent than plain `.caption`
/// secondary text so it stays legible as an orientation cue while comparing.
private struct ColumnTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(8)
    }
}

extension String {
    /// The last portion of a growing stream, for cheap live display. SwiftUI `Text` lays out
    /// its entire string on every update and does not virtualize, so rendering the full,
    /// ever-growing stream re-lays-out a larger and larger string and lags badly on long
    /// output. While generation is in flight only the newest text matters; the complete text
    /// (and the formatted diff) is shown once it finishes.
    ///
    /// The window is deliberately small — a few paragraphs, about one screenful. Every
    /// published update re-measures and re-lays-out the whole string, and that cost is
    /// paid ~10x/sec for the entire run, so a wider window buys nothing readable and
    /// costs real generation speed.
    func streamingTail(maxChars: Int = 1200) -> String {
        guard count > maxChars else { return self }
        let tail = suffix(maxChars)
        if let newline = tail.firstIndex(of: "\n") {
            return "…\n" + tail[tail.index(after: newline)...]
        }
        return "…" + tail
    }
}
