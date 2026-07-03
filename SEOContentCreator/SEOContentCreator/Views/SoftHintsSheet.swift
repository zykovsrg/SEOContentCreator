import SwiftUI
import SwiftData

struct SoftHintsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let topic: Topic

    @State private var hints: [SoftHint] = []
    @State private var selectedHintID: UUID?

    private var text: String { topic.currentVersion?.text ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if text.isEmpty {
                ContentUnavailableView("Нет текста для проверки", systemImage: "text.alignleft")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            MultiHighlightedText(text: text, marks: marks, emphasized: emphasizedRange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .onChange(of: selectedHintID) { _, _ in
                            guard let index = emphasizedParagraphIndex else { return }
                            withAnimation { proxy.scrollTo(index, anchor: .center) }
                        }
                    }
                    Divider()
                    panel.frame(width: 320)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear(perform: recompute)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Подсказки").font(.headline)
                Text("Грубые алгоритмические подсказки. Ничего не сохраняется.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Закрыть") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Найдено: \(hints.count)").font(.headline).foregroundStyle(.secondary).padding(8)
            Divider()
            if hints.isEmpty {
                ContentUnavailableView("Подсказок нет", systemImage: "checkmark.seal")
            } else {
                List(hints) { hint in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hint.kind.title).font(.subheadline).bold()
                            .foregroundStyle(hint.kind.highlightColor)
                        Text(hint.message).font(.callout)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedHintID = hint.id }
                    .listRowBackground(selectedHintID == hint.id ? Color.accentColor.opacity(0.12) : Color.clear)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var marks: [MultiHighlightedText.Mark] {
        hints.map { .init(range: $0.range, color: $0.kind.highlightColor) }
    }

    private var emphasizedRange: Range<String.Index>? {
        guard let id = selectedHintID else { return nil }
        return hints.first { $0.id == id }?.range
    }

    private var emphasizedParagraphIndex: Int? {
        guard let range = emphasizedRange else { return nil }
        return TextParagraphs.index(of: range.lowerBound, in: TextParagraphs.ranges(in: text))
    }

    private func recompute() {
        let settings = fetchDictionary().settings
        hints = SoftHints.analyze(text: text, settings: settings)
    }

    /// Fetch the single EditorDictionary, seeding if missing (mirrors fetchTemplate).
    private func fetchDictionary() -> EditorDictionary {
        if let found = (try? context.fetch(FetchDescriptor<EditorDictionary>()))?.first {
            return found
        }
        EditorDictionarySeeder.seedIfNeeded(in: context)
        return (try? context.fetch(FetchDescriptor<EditorDictionary>()))?.first
            ?? EditorDictionaryDefaults.make()
    }
}
