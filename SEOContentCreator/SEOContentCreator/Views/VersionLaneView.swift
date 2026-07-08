import SwiftUI
import SwiftData

struct VersionLaneView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    var onCompare: (ArticleVersion) -> Void

    @State private var groupByStage = false
    @State private var selecting = false
    @State private var selection: [UUID] = []
    @State private var comparePair: ComparePair?

    private struct ComparePair: Identifiable {
        let id = UUID()
        let a: ArticleVersion
        let b: ArticleVersion
    }

    private var versions: [ArticleVersion] {
        topic.versions.filter(\.isVisibleInVersionLane).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Вид", selection: $groupByStage) {
                    Text("По времени").tag(false)
                    Text("По этапам").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(selecting)

                HStack {
                    if selecting {
                        Button("Сравнить выбранные (\(selection.count))") { startCompare() }
                            .disabled(selection.count != 2)
                            .controlSize(.small)
                        Spacer()
                        Button("Отмена") { selecting = false; selection = [] }
                            .controlSize(.small)
                    } else {
                        Spacer()
                        Button("Сравнить версии") { selecting = true }
                            .controlSize(.small)
                    }
                }
            }
            .padding(12)
            Divider()

            if versions.isEmpty {
                ContentUnavailableView("Версий пока нет", systemImage: "clock.arrow.circlepath")
            } else {
                List {
                    if groupByStage {
                        ForEach(stageGroups, id: \.0) { stage, items in
                            Section(stage) { ForEach(items) { row($0) } }
                        }
                    } else {
                        ForEach(versions) { row($0) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $comparePair) { pair in
            VersionCompareView(versionA: pair.a, versionB: pair.b)
        }
    }

    private func startCompare() {
        guard selection.count == 2,
              let a = versions.first(where: { $0.uuid == selection[0] }),
              let b = versions.first(where: { $0.uuid == selection[1] }) else { return }
        comparePair = ComparePair(a: a, b: b)
        selecting = false
        selection = []
    }

    private var stageGroups: [(String, [ArticleVersion])] {
        Dictionary(grouping: versions, by: { $0.stageTitle })
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private func row(_ v: ArticleVersion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if selecting {
                    // Tap is handled by the row-level gesture below — no separate
                    // gesture here, otherwise a tap on the box toggles twice.
                    let isSelected = selection.contains(v.uuid)
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.stageTitle).font(.subheadline)
                    Text("\(v.source.title) · \(v.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if topic.currentVersionID == v.uuid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Текущая версия")
                }
            }
            if !selecting {
                HStack(spacing: 8) {
                    Button("Сравнить") { onCompare(v) }
                        .controlSize(.small)
                    Button("Сделать текущей") { makeCurrent(v) }
                        .controlSize(.small)
                        .disabled(topic.currentVersionID == v.uuid)
                    Spacer()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting { selection = compareSelectionToggle(current: selection, tapped: v.uuid) }
        }
    }

    private func makeCurrent(_ v: ArticleVersion) {
        // Already current — nothing to roll back to.
        guard topic.currentVersionID != v.uuid else { return }
        let rollback = ArticleVersion(stageLabel: "rollback", source: .rollback, text: v.text)
        rollback.note = "Откат к версии: \(v.stageTitle)"
        rollback.topic = topic
        context.insert(rollback)
        topic.currentVersionID = rollback.uuid
        topic.updatedAt = .now
    }
}
