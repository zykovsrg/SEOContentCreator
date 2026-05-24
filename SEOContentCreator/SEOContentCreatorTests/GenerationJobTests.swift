import Testing
import Foundation
@testable import SEOContentCreator

struct GenerationJobTests {
    @Test func newJobIsRunning() {
        let job = GenerationJob(stage: .draft, agentName: "ИИ-автор", modelName: "gpt-4.1")
        #expect(job.status == .running)
        #expect(job.stageRaw == "draft")
        #expect(job.finishedAt == nil)
    }

    @Test func canMarkSuccess() {
        let job = GenerationJob(stage: .draft, agentName: "ИИ-автор", modelName: "gpt-4.1")
        job.status = .success
        job.finishedAt = .now
        #expect(job.status == .success)
        #expect(job.finishedAt != nil)
    }

    @Test func labelInitProducesReadableImageTitle() {
        let job = GenerationJob(stageLabel: "image", agentName: "Генератор изображений", modelName: "gpt-image-1")
        #expect(job.status == .running)
        #expect(job.stageTitle == "Изображение")
        #expect(job.agentName == "Генератор изображений")
    }
}
