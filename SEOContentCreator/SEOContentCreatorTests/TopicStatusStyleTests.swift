// TopicStatusStyleTests.swift
import Testing
@testable import SEOContentCreator

struct TopicStatusStyleTests {
    @Test func ideaIsNeutral() {
        #expect(TopicStatus.idea.tone == .neutral)
    }
    @Test func readyIsActive() {
        #expect(TopicStatus.ready.tone == .active)
    }
    @Test func publishedIsPositive() {
        #expect(TopicStatus.published.tone == .positive)
    }
}
