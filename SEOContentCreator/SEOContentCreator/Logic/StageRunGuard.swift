import Foundation

enum StageRunGuard {
    static func messagePreventingRun(stage: PipelineStage, topic: Topic) -> String? {
        if stage == .draft {
            if BriefValidation.canStartDraft(title: topic.title, hasDirection: topic.direction != nil) {
                return nil
            }
            if topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Перед черновиком заполните название темы в брифе."
            }
            return "Перед черновиком выберите направление в брифе."
        }
        if stage.kind == .checking {
            let text = topic.currentVersion?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                return "Перед проверкой нужен текст статьи — сначала сгенерируйте черновик."
            }
        }
        return nil
    }
}
