import SwiftUI

struct StageBarView: View {
    @Binding var selectedStage: PipelineStage
    var topic: Topic

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PipelineStage.allCases) { stage in
                Button {
                    selectedStage = stage
                } label: {
                    Text(stage.title)
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
}
