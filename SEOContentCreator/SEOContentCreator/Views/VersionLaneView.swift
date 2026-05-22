import SwiftUI
import SwiftData

struct VersionLaneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    var onCompare: (ArticleVersion) -> Void

    @State private var groupByStage = false

    private var versions: [ArticleVersion] {
        topic.versions.filter { !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Вид", selection: $groupByStage) {
                Text("По времени").tag(false)
                Text("По этапам").tag(true)
            }.pickerStyle(.segmented)

            List {
                if groupByStage {
                    ForEach(stageGroups, id: \.0) { stage, items in
                        Section(stage) { ForEach(items) { row($0) } }
                    }
                } else {
                    ForEach(versions) { row($0) }
                }
            }

            HStack { Spacer(); Button("Закрыть") { dismiss() } }
        }
        .padding()
        .frame(width: 520, height: 520)
    }

    private var stageGroups: [(String, [ArticleVersion])] {
        Dictionary(grouping: versions, by: { $0.stageTitle })
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private func row(_ v: ArticleVersion) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(v.stageTitle).font(.subheadline)
                Text("\(v.source.title) · \(v.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if topic.currentVersionID == v.uuid {
                Label("Текущая", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).labelStyle(.iconOnly)
            }
            Button("Сравнить") { onCompare(v); dismiss() }
            Button("Сделать текущей") { makeCurrent(v) }
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
