import Foundation
import SwiftData

@Model
final class KnowledgeNode {
    var title: String
    var content: String
    var nodeTypeRaw: String
    var sources: [String]          // URLs; meaningful for `direction` nodes
    var createdAt: Date

    var parent: KnowledgeNode?
    @Relationship(deleteRule: .cascade, inverse: \KnowledgeNode.parent)
    var children: [KnowledgeNode]

    init(
        title: String,
        type: NodeType,
        content: String = "",
        sources: [String] = [],
        parent: KnowledgeNode? = nil
    ) {
        self.title = title
        self.nodeTypeRaw = type.rawValue
        self.content = content
        self.sources = sources
        self.createdAt = .now
        self.parent = parent
        self.children = []
    }

    var nodeType: NodeType {
        get { NodeType(rawValue: nodeTypeRaw) ?? .folder }
        set { nodeTypeRaw = newValue.rawValue }
    }

    func addChild(title: String, type: NodeType, content: String = "", sources: [String] = []) -> KnowledgeNode {
        let child = KnowledgeNode(title: title, type: type, content: content, sources: sources, parent: self)
        children.append(child)
        return child
    }

    /// For OutlineGroup: nil for leaves so no disclosure triangle shows.
    var childrenOrNil: [KnowledgeNode]? {
        children.isEmpty ? nil : children
    }
}
