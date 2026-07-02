import Foundation
import SwiftData

enum VersionActions {
    /// Build a hybrid text: take paragraph i from `new` if i is accepted, else from `old`.
    /// Paragraphs are aligned by index; if `new` has more paragraphs, extra accepted ones are appended.
    static func assembleHybrid(old: String, new: String, acceptedNewIndices: Set<Int>) -> String {
        let oldParas = ParagraphDiff.paragraphs(old)
        let newParas = ParagraphDiff.paragraphs(new)
        let count = max(oldParas.count, newParas.count)
        var result: [String] = []
        for i in 0..<count {
            if acceptedNewIndices.contains(i), i < newParas.count {
                result.append(newParas[i])
            } else if i < oldParas.count {
                result.append(oldParas[i])
            }
        }
        return result.joined(separator: "\n\n")
    }

    /// Saves a manually edited full text as a new current version of the topic.
    /// Manual edit is a sweeping, cross-cutting action per the project invariant
    /// that hand editing must stay available at any pipeline stage.
    @discardableResult
    static func applyManualEdit(topic: Topic, newText: String, in context: ModelContext) -> ArticleVersion {
        let version = ArticleVersion(stageLabel: "manualEdit", source: .manualEdit, text: newText)
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
        return version
    }
}
