import Foundation

enum KnowledgeNodePath {
    static func path(for node: KnowledgeNode) -> [KnowledgeNode] {
        var result: [KnowledgeNode] = []
        var current: KnowledgeNode? = node
        while let item = current {
            result.insert(item, at: 0)
            current = item.parent
        }
        return result
    }
}
