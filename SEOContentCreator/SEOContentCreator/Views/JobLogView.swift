import SwiftUI
import SwiftData

struct JobLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    private var jobs: [GenerationJob] {
        topic.jobs.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Лог темы").font(.headline)
            List(jobs) { job in
                HStack {
                    icon(for: job.status)
                    VStack(alignment: .leading) {
                        Text(job.stageTitle).font(.subheadline)
                        Text("\(job.agentName) · \(job.modelName) · \(job.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = job.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Spacer()
                }
            }
            HStack { Spacer(); Button("Закрыть") { dismiss() } }
        }
        .padding()
        .frame(width: 520, height: 440)
    }

    @ViewBuilder private func icon(for status: JobStatus) -> some View {
        switch status {
        case .running:   Image(systemName: "hourglass").foregroundStyle(.orange)
        case .success:   Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:     Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }
}
