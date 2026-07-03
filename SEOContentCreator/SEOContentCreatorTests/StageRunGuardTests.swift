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

    @Test func structureStageRemainsFlexibleOnEmptyText() {
        let topic = Topic(title: "Тема", articleType: .disease)
        #expect(StageRunGuard.messagePreventingRun(stage: .structure, topic: topic) == nil)
    }

    @Test func checkingStageWithoutTextReturnsMessage() {
        let topic = Topic(title: "Тема", articleType: .disease)
        #expect(StageRunGuard.messagePreventingRun(stage: .seoCheck, topic: topic) != nil)
    }

    @Test func checkingStageWithBlankTextReturnsMessage() {
        let topic = Topic(title: "Тема", articleType: .disease)
        let version = ArticleVersion(stage: .draft, source: .generated, text: "   \n  ")
        topic.versions = [version]
        topic.currentVersionID = version.uuid
        #expect(StageRunGuard.messagePreventingRun(stage: .factCheck, topic: topic) != nil)
    }

    @Test func checkingStageWithTextCanRun() {
        let topic = Topic(title: "Тема", articleType: .disease)
        let version = ArticleVersion(stage: .draft, source: .generated, text: "Готовый текст статьи")
        topic.versions = [version]
        topic.currentVersionID = version.uuid
        #expect(StageRunGuard.messagePreventingRun(stage: .seoCheck, topic: topic) == nil)
    }
}
