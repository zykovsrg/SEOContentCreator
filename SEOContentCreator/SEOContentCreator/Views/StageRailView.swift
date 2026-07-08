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
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Этапы")
                    .font(.headline)
                Text(headerHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ForEach(StagePipeline.workflow) { stage in
                Button { selectedStage = stage } label: {
                    row(for: stage)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 250)
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
        HStack(alignment: .top, spacing: 12) {
            marker(for: stage)
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                Text(agentName(for: stage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(selected ? Color.rowHighlight : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func marker(for stage: PipelineStage) -> some View {
        if isCompleted(stage) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        } else if stage == nextStage {
            Image(systemName: "circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.caption)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Color.secondary.opacity(0.45))
                .font(.title3)
                .frame(width: 22, height: 22)
        }
    }

    private func agentName(for stage: PipelineStage) -> String {
        roles.first { $0.key == stage.roleKey }?.name ?? stage.agentName
    }
}
