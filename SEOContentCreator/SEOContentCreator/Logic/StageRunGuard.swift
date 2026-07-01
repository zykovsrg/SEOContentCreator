import Foundation

enum StageRunGuard {
    static func messagePreventingRun(stage: PipelineStage, topic: Topic) -> String? {
        guard stage == .draft else { return nil }
        if BriefValidation.canStartDraft(title: topic.title, hasDirection: topic.direction != nil) {
            return nil
        }
        if topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Перед черновиком заполните название темы в брифе."
        }
        return "Перед черновиком выберите направление в брифе."
    }
}
