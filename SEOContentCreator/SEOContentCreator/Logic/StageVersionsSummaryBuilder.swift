import Foundation

/// Renders the last accepted version of each pipeline stage for `topic`, for the
/// `.promptAnalysis` stage's `{{история_версий_по_этапам}}` placeholder
/// (FT-20260703-003). Stages without an accepted version are skipped.
enum StageVersionsSummaryBuilder {
    static func build(topic: Topic) -> String {
        var parts: [String] = []

        let structureText = topic.structureText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !structureText.isEmpty {
            parts.append("## Структура\n\(structureText)")
        }

        for stage in PipelineStage.allCases where stage.kind != .action && stage.kind != .analysis {
            guard stage != .structure else { continue }
            let latest = topic.versions
                .filter { $0.stageRaw == stage.rawValue && $0.status == .accepted }
                .max { $0.createdAt < $1.createdAt }
            guard let latest else { continue }
            parts.append("## \(stage.title)\n\(latest.text)")
        }

        return parts.joined(separator: "\n\n")
    }
}
