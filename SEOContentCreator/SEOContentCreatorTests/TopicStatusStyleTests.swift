// TopicStatusStyleTests.swift
import Testing
@testable import SEOContentCreator

struct TopicStatusStyleTests {
    @Test func briefIsNeutral() {
        #expect(TopicStatus.brief.tone == .neutral)
    }
    @Test func inProgressIsActive() {
        #expect(TopicStatus.inProgress(.draft).tone == .active)
    }
    @Test func publishedIsPositive() {
        #expect(TopicStatus.published.tone == .positive)
    }
    @Test func doneIsPositive() {
        #expect(TopicStatus.done.tone == .positive)
    }
}
