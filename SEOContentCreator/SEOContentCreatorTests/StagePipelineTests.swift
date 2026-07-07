// StagePipelineTests.swift
import Testing
@testable import SEOContentCreator

struct StagePipelineTests {
    @Test func workflowIsEightStagesWithoutPromptAnalysis() {
        #expect(StagePipeline.workflow.count == 8)
        #expect(StagePipeline.workflow.contains(.promptAnalysis) == false)
        #expect(StagePipeline.workflow.first == .structure)
        #expect(StagePipeline.workflow.last == .images)
    }

    @Test func nothingCompletedMakesFirstStageCurrent() {
        let states = StagePipeline.states { _ in false }
        #expect(states.first?.state == .current)
        #expect(states.dropFirst().allSatisfy { $0.state == .upcoming })
        #expect(StagePipeline.completedCount { _ in false } == 0)
        #expect(StagePipeline.nextStage { _ in false } == .structure)
    }

    @Test func completedPrefixMarksNextAsCurrent() {
        let done: Set<PipelineStage> = [.structure, .draft, .productBlocks]
        let states = StagePipeline.states { done.contains($0) }
        #expect(states[0].state == .done)
        #expect(states[2].state == .done)
        #expect(states[3].state == .current)   // semanticsInText
        #expect(states[4].state == .upcoming)
        #expect(StagePipeline.completedCount { done.contains($0) } == 3)
        #expect(StagePipeline.nextStage { done.contains($0) } == .semanticsInText)
    }

    @Test func allCompletedHasNoCurrentAndNoNext() {
        let states = StagePipeline.states { _ in true }
        #expect(states.allSatisfy { $0.state == .done })
        #expect(StagePipeline.completedCount { _ in true } == 8)
        #expect(StagePipeline.nextStage { _ in true } == nil)
    }
}
