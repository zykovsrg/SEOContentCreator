import SwiftUI

struct VersionCompareView: View {
    @Environment(\.dismiss) private var dismiss
    let versionA: ArticleVersion
    let versionB: ArticleVersion

    /// Older version goes left, newer goes right, regardless of pick order.
    private var older: ArticleVersion {
        versionA.createdAt <= versionB.createdAt ? versionA : versionB
    }
    private var newer: ArticleVersion {
        versionA.createdAt <= versionB.createdAt ? versionB : versionA
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                column(version: older, lines: ParagraphDiff.oldSide(old: older.text, new: newer.text))
                Divider()
                column(version: newer, lines: ParagraphDiff.newSide(old: older.text, new: newer.text))
            }
            Divider()
            HStack { Spacer(); Button("Закрыть") { dismiss() }.keyboardShortcut(.defaultAction) }
                .padding(8)
        }
        .frame(width: 760, height: 560)
    }

    private func column(version: ArticleVersion, lines: [ParagraphDiffLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(version.stageTitle).font(.subheadline).bold()
                Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .textSelection(.enabled)
                            .strikethrough(line.kind == .removed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(background(for: line.kind))
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func background(for kind: ParagraphDiffKind) -> Color {
        switch kind {
        case .added:   return Color.green.opacity(0.18)
        case .removed: return Color.red.opacity(0.14)
        case .unchanged: return .clear
        }
    }
}
