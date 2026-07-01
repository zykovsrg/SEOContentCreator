import Foundation
import SwiftData

enum ArticleVersionStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case rejected
    case archived
}

@Model
final class ArticleVersion {
    var uuid: UUID
    var stageRaw: String          // PipelineStage.rawValue, or "manualEdit"/"rollback"/"importFromDocs"
    var sourceRaw: String
    var statusRaw: String?
    var text: String
    var h1: String?
    var seoTitle: String?
    var seoDescription: String?
    var agentName: String?
    var templateID: UUID?
    var modelName: String?
    var note: String?
    var isArchived: Bool
    var createdAt: Date

    @Relationship var topic: Topic?

    /// Designated init with an arbitrary stage label string (used for manualEdit/rollback).
    init(
        stageLabel: String,
        source: VersionSource,
        text: String,
        agentName: String? = nil,
        templateID: UUID? = nil,
        modelName: String? = nil
    ) {
        self.uuid = UUID()
        self.stageRaw = stageLabel
        self.sourceRaw = source.rawValue
        self.statusRaw = ArticleVersionStatus.accepted.rawValue
        self.text = text
        self.agentName = agentName
        self.templateID = templateID
        self.modelName = modelName
        self.isArchived = false
        self.createdAt = .now
    }

    /// Convenience init for a known pipeline stage.
    convenience init(
        stage: PipelineStage,
        source: VersionSource,
        text: String,
        agentName: String? = nil,
        templateID: UUID? = nil,
        modelName: String? = nil
    ) {
        self.init(stageLabel: stage.rawValue, source: source, text: text,
                  agentName: agentName, templateID: templateID, modelName: modelName)
    }

    var source: VersionSource {
        get { VersionSource(rawValue: sourceRaw) ?? .generated }
        set { sourceRaw = newValue.rawValue }
    }

    var status: ArticleVersionStatus {
        get {
            if isArchived { return .archived }
            guard let statusRaw, let value = ArticleVersionStatus(rawValue: statusRaw) else {
                return .accepted
            }
            return value
        }
        set {
            statusRaw = newValue.rawValue
            isArchived = newValue == .archived
        }
    }

    var isVisibleInVersionLane: Bool {
        status == .accepted
    }

    var stageTitle: String {
        if let stage = PipelineStage(rawValue: stageRaw) { return stage.title }
        switch stageRaw {
        case "manualEdit":     return "Ручная правка"
        case "rollback":       return "Откат"
        case "importFromDocs":       return "Импорт из Docs"
        case "skillApplied":        return "Правка скиллом"
        case "fragmentRegenerated": return "Регенерация фрагмента"
        default:               return stageRaw
        }
    }
}
