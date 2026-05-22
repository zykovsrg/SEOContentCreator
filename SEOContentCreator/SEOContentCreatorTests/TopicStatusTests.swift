import Testing
import Foundation
@testable import SEOContentCreator

struct TopicStatusTests {
    @Test func ideaWhenDirectionMissing() {
        let t = Topic(title: "Тема", articleType: .info)
        #expect(TopicStatus.compute(for: t) == .idea)
    }

    @Test func readyWhenTitleAndDirectionPresent() {
        let t = Topic(title: "Тема", articleType: .info, direction: "Лучевая терапия")
        #expect(TopicStatus.compute(for: t) == .ready)
    }

    @Test func publishedWhenPublishedAtSet() {
        let t = Topic(title: "Тема", articleType: .info, direction: "Лучевая терапия")
        t.publishedAt = .now
        #expect(TopicStatus.compute(for: t) == .published)
    }
}
