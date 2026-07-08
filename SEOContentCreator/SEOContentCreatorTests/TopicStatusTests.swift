import Testing
import Foundation
@testable import SEOContentCreator

struct TopicStatusTests {
    @Test func briefWhenDirectionMissing() {
        let t = Topic(title: "Тема", articleType: .info)
        #expect(TopicStatus.compute(for: t) == .brief)
        #expect(TopicStatus.compute(for: t).label == "Бриф")
    }

    @Test func briefWhenNothingGeneratedYet() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction)
        let t = Topic(title: "Тема", articleType: .info, direction: dir)
        #expect(TopicStatus.compute(for: t) == .brief)
    }

    @Test func nextStageWhenWorkflowStarted() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction)
        let t = Topic(title: "Тема", articleType: .info, direction: dir)
        t.structureText = "План"
        #expect(TopicStatus.compute(for: t) == .inProgress(.draft))
        #expect(TopicStatus.compute(for: t).label == "Черновик")
    }

    @Test func doneWhenWorkflowCompleted() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction)
        let t = Topic(title: "Тема", articleType: .info, direction: dir)
        t.structureText = "План"
        for stage in StagePipeline.workflow where stage != .structure {
            let version = ArticleVersion(stage: stage, source: .generated, text: "Текст")
            version.status = ArticleVersionStatus.accepted
            version.topic = t
            t.versions.append(version)
            if stage == .finalReview {
                t.currentVersionID = version.uuid
            }
        }
        t.images.append(GeneratedImage(role: .cover, data: Data(), promptUsed: "p"))
        t.promptRecommendations.append(PromptRecommendation(problem: "y", location: "x", suggestion: "z"))
        #expect(TopicStatus.compute(for: t) == .done)
        #expect(TopicStatus.compute(for: t).label == "Готово")
    }

    @Test func publishedWhenPublishedAtSet() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction)
        let t = Topic(title: "Тема", articleType: .info, direction: dir)
        t.publishedAt = .now
        #expect(TopicStatus.compute(for: t) == .published)
    }
}
