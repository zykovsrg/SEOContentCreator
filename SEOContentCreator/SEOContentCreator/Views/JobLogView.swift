import SwiftUI
import SwiftData

struct JobLogView: View {
    @Bindable var topic: Topic

    private var jobs: [GenerationJob] {
        topic.jobs.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Лог темы").font(.headline).padding(12)
            Divider()
            if jobs.isEmpty {
                ContentUnavailableView("Лог пуст", systemImage: "doc.text")
            } else {
                List(jobs) { job in
                    HStack(alignment: .top, spacing: 8) {
                        icon(for: job.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.stageTitle).font(.subheadline)
                            Text("\(job.agentName) · \(job.modelName)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(job.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if let error = job.errorMessage {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
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
