import Foundation
import SwiftData

/// Bridges the transient `Remark` list a checking-stage run produces with its
/// durable `PersistedRemark` records, so an in-progress review survives an app
/// restart (FT-20260702-011).
enum RemarkPersistence {
    static func persist(remarks: [Remark], job: GenerationJob, in context: ModelContext) {
        for remark in remarks {
            let persisted = PersistedRemark(remark: remark)
            persisted.job = job
            context.insert(persisted)
        }
    }

    static func updateStatus(remarkID: UUID, status: RemarkDecisionStatus, jobID: UUID?, topic: Topic) {
        guard let jobID, let job = topic.jobs.first(where: { $0.uuid == jobID }) else { return }
        job.persistedRemarks.first(where: { $0.uuid == remarkID })?.status = status
    }

    static func updateSuggestion(remarkID: UUID, suggestion: String, jobID: UUID?, topic: Topic) {
        guard let jobID, let job = topic.jobs.first(where: { $0.uuid == jobID }) else { return }
        job.persistedRemarks.first(where: { $0.uuid == remarkID })?.suggestion = suggestion
    }

    static func resolve(jobID: UUID?, topic: Topic) {
        guard let jobID, let job = topic.jobs.first(where: { $0.uuid == jobID }) else { return }
        job.reviewResolved = true
    }

    struct RestoredReview {
        var jobID: UUID
        var remarks: [Remark]
        var accepted: Set<UUID>
        var rejected: Set<UUID>
    }

    /// Finds the most recent checking-stage review that was never resolved
    /// (app likely closed mid-review) and reconstructs its remarks + decisions.
    static func restoreLatestUnresolved(topic: Topic) -> RestoredReview? {
        let candidate = topic.jobs
            .filter {
                $0.status == .success
                    && !$0.reviewResolved
                    && PipelineStage(rawValue: $0.stageRaw)?.kind == .checking
                    && !$0.persistedRemarks.isEmpty
            }
            .max { $0.startedAt < $1.startedAt }
        guard let job = candidate else { return nil }
        let remarks = job.persistedRemarks.map(\.asRemark)
        let accepted = Set(job.persistedRemarks.filter { $0.status == .accepted }.map(\.uuid))
        let rejected = Set(job.persistedRemarks.filter { $0.status == .rejected }.map(\.uuid))
        return RestoredReview(jobID: job.uuid, remarks: remarks, accepted: accepted, rejected: rejected)
    }
}
