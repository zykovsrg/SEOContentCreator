import SwiftUI
import SwiftData

struct StageBarView: View {
    @Binding var selectedStage: PipelineStage
    var topic: Topic
    @Query private var roles: [AIRole]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PipelineStage.allCases) { stage in
                Button {
                    selectedStage = stage
                } label: {
                    HStack(spacing: 6) {
                        if StageProgress.isCompleted(stage, versions: topic.versions, structureText: topic.structureText) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        VStack(spacing: 2) {
                            Text(stage.title)
                            Text(agentName(for: stage))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(selectedStage == stage ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func agentName(for stage: PipelineStage) -> String {
        roles.first { $0.key == stage.roleKey }?.name ?? stage.agentName
    }
}
