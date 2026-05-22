import Testing
import Foundation
@testable import SEOContentCreator

struct TopicStatusTests {
    @Test func ideaWhenDirectionMissing() {
        let t = Topic(title: "Тема", articleType: .info)
        #expect(TopicStatus.compute(for: t) == .idea)
    }

    @Test func readyWhenTitleAndDirectionPresent() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction)
        let t = Topic(title: "Тема", articleType: .info, direction: dir)
        #expect(TopicStatus.compute(for: t) == .ready)
    }

    @Test func publishedWhenPublishedAtSet() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction)
        let t = Topic(title: "Тема", articleType: .info, direction: dir)
        t.publishedAt = .now
        #expect(TopicStatus.compute(for: t) == .published)
    }
}
