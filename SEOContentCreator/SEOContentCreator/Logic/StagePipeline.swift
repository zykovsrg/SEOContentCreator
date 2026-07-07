// StagePipeline.swift
import Foundation

enum StageState: Equatable {
    case done       // completed
    case current    // first not-yet-completed workflow stage
    case upcoming    // not reached yet
}

enum StagePipeline {
    /// Article workflow in order, used for the progress dots and the rail
    /// header count. Excludes `.promptAnalysis` (analysis/learning).
    static let workflow: [PipelineStage] = [
        .structure, .draft, .productBlocks, .semanticsInText,
        .seoCheck, .factCheck, .finalReview, .images
    ]

    static func completedCount(isCompleted: (PipelineStage) -> Bool) -> Int {
        workflow.filter(isCompleted).count
    }

    static func nextStage(isCompleted: (PipelineStage) -> Bool) -> PipelineStage? {
        workflow.first { !isCompleted($0) }
    }

    static func states(isCompleted: (PipelineStage) -> Bool) -> [(stage: PipelineStage, state: StageState)] {
        let next = nextStage(isCompleted: isCompleted)
        return workflow.map { stage in
            if isCompleted(stage) { return (stage, .done) }
            if stage == next { return (stage, .current) }
            return (stage, .upcoming)
        }
    }
}
