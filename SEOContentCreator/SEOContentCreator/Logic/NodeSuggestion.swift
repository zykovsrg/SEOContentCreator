import Foundation

enum NodeSuggestion {
    /// Suggest direction nodes whose title appears (case-insensitive) in the topic title.
    static func suggestDirections(forTopicTitle title: String, from nodes: [KnowledgeNode]) -> [KnowledgeNode] {
        let lowerTitle = title.lowercased()
        return nodes.filter { node in
            node.nodeType == .direction
            && !node.title.isEmpty
            && lowerTitle.contains(node.title.lowercased())
        }
    }
}
