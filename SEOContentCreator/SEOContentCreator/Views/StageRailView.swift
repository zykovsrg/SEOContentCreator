// StageRailView.swift
import SwiftUI
import SwiftData

struct StageRailView: View {
    @Binding var selectedStage: PipelineStage
    var topic: Topic
    @Query private var roles: [AIRole]

    private func isCompleted(_ stage: PipelineStage) -> Bool {
        StageProgress.isCompleted(
            stage, versions: topic.versions, structureText: topic.structureText,
            hasImages: !topic.images.filter { !$0.isArchived }.isEmpty,
            hasPromptRecommendations: !topic.promptRecommendations.isEmpty
        )
    }

    private var completedCount: Int {
        StagePipeline.completedCount(isCompleted: isCompleted)
    }

    private var nextStage: PipelineStage? {
        StagePipeline.nextStage(isCompleted: isCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Этапы").font(.subheadline).fontWeight(.semibold)
                Text(headerHint).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)

            ForEach(PipelineStage.allCases) { stage in
                Button { selectedStage = stage } label: {
                    row(for: stage)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 200)
    }

    private var headerHint: String {
        if let next = nextStage {
            return "\(completedCount) из \(StagePipeline.workflow.count) · дальше: \(next.title)"
        }
        return "\(completedCount) из \(StagePipeline.workflow.count) · всё готово"
    }

    @ViewBuilder
    private func row(for stage: PipelineStage) -> some View {
        let selected = selectedStage == stage
        HStack(alignment: .top, spacing: 9) {
            marker(for: stage)
            VStack(alignment: .leading, spacing: 1) {
                Text(stage.title)
                    .font(.callout)
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                Text(agentName(for: stage))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func marker(for stage: PipelineStage) -> some View {
        if isCompleted(stage) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.body)
        } else if stage == nextStage {
            Image(systemName: "circle.fill")
                .foregroundStyle(Color.accentColor).font(.caption)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Color.secondary.opacity(0.5)).font(.caption)
                .frame(width: 16, height: 16)
        }
    }

    private func agentName(for stage: PipelineStage) -> String {
        roles.first { $0.key == stage.roleKey }?.name ?? stage.agentName
    }
}
