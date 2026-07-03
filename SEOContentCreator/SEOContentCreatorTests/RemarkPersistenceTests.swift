import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct RemarkPersistenceTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, PromptRecommendation.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, PersistedRemark.self, StageTemplate.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeJob(stage: PipelineStage = .finalReview, topic: Topic, in context: ModelContext) -> GenerationJob {
        let job = GenerationJob(stage: stage, agentName: "ИИ-редактор", modelName: "gpt-4.1")
        job.topic = topic
        job.status = .success
        context.insert(job)
        return job
    }

    @Test func persistCreatesOnePersistedRemarkPerRemarkWithSameID() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let job = makeJob(topic: topic, in: context)
        let remark = Remark(category: "Стиль", quote: "было", suggestion: "стало", explanation: "почему")

        RemarkPersistence.persist(remarks: [remark], job: job, in: context)

        #expect(job.persistedRemarks.count == 1)
        #expect(job.persistedRemarks.first?.uuid == remark.id)
        #expect(job.persistedRemarks.first?.status == .pending)
    }

    @Test func updateStatusChangesMatchingPersistedRemark() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let job = makeJob(topic: topic, in: context)
        let remark = Remark(category: "Стиль", quote: "было", suggestion: "стало", explanation: "почему")
        RemarkPersistence.persist(remarks: [remark], job: job, in: context)

        RemarkPersistence.updateStatus(remarkID: remark.id, status: .accepted, jobID: job.uuid, topic: topic)

        #expect(job.persistedRemarks.first?.status == .accepted)
    }

    @Test func updateSuggestionChangesMatchingPersistedRemark() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let job = makeJob(topic: topic, in: context)
        let remark = Remark(category: "Стиль", quote: "было", suggestion: "стало", explanation: "почему")
        RemarkPersistence.persist(remarks: [remark], job: job, in: context)

        RemarkPersistence.updateSuggestion(remarkID: remark.id, suggestion: "доработано", jobID: job.uuid, topic: topic)

        #expect(job.persistedRemarks.first?.suggestion == "доработано")
    }

    @Test func resolveMarksJobReviewResolved() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let job = makeJob(topic: topic, in: context)
        #expect(job.reviewResolved == false)

        RemarkPersistence.resolve(jobID: job.uuid, topic: topic)

        #expect(job.reviewResolved == true)
    }

    @Test func restoreLatestUnresolvedReturnsNilWhenNoUnresolvedReview() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let job = makeJob(topic: topic, in: context)
        let remark = Remark(category: "Стиль", quote: "было", suggestion: "стало", explanation: "почему")
        RemarkPersistence.persist(remarks: [remark], job: job, in: context)
        job.reviewResolved = true

        #expect(RemarkPersistence.restoreLatestUnresolved(topic: topic) == nil)
    }

    @Test func restoreLatestUnresolvedReconstructsRemarksAndDecisions() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let job = makeJob(topic: topic, in: context)
        let accepted = Remark(category: "A", quote: "q1", suggestion: "s1", explanation: "e1")
        let rejected = Remark(category: "B", quote: "q2", suggestion: "s2", explanation: "e2")
        let pending = Remark(category: "C", quote: "q3", suggestion: "s3", explanation: "e3")
        RemarkPersistence.persist(remarks: [accepted, rejected, pending], job: job, in: context)
        RemarkPersistence.updateStatus(remarkID: accepted.id, status: .accepted, jobID: job.uuid, topic: topic)
        RemarkPersistence.updateStatus(remarkID: rejected.id, status: .rejected, jobID: job.uuid, topic: topic)

        let restored = try #require(RemarkPersistence.restoreLatestUnresolved(topic: topic))

        #expect(restored.jobID == job.uuid)
        #expect(Set(restored.remarks.map(\.id)) == Set([accepted.id, rejected.id, pending.id]))
        #expect(restored.accepted == [accepted.id])
        #expect(restored.rejected == [rejected.id])
    }

    @Test func restoreLatestUnresolvedIgnoresNonCheckingStages() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        // A draft job has no remarks in practice, but guard against a stray one being picked up.
        let job = makeJob(stage: .draft, topic: topic, in: context)
        let remark = Remark(category: "A", quote: "q", suggestion: "s", explanation: "e")
        RemarkPersistence.persist(remarks: [remark], job: job, in: context)

        #expect(RemarkPersistence.restoreLatestUnresolved(topic: topic) == nil)
    }
}
