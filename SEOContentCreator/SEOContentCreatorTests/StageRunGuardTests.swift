import Testing
@testable import SEOContentCreator

struct StageRunGuardTests {
    @Test func draftWithoutDirectionReturnsMessage() {
        let topic = Topic(title: "Тема", articleType: .disease)
        #expect(StageRunGuard.messagePreventingRun(stage: .draft, topic: topic) == "Перед черновиком выберите направление в брифе.")
    }

    @Test func draftWithDirectionCanRun() {
        let direction = KnowledgeNode(title: "Онкология", type: .direction)
        let topic = Topic(title: "Тема", articleType: .disease, direction: direction)
        #expect(StageRunGuard.messagePreventingRun(stage: .draft, topic: topic) == nil)
    }

    @Test func nonDraftStagesRemainFlexible() {
        let topic = Topic(title: "Тема", articleType: .disease)
        #expect(StageRunGuard.messagePreventingRun(stage: .seoCheck, topic: topic) == nil)
    }
}
