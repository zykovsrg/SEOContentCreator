import Foundation

struct KnowledgeTreeFilter {
    var searchText: String = ""
    var types: Set<NodeType> = []

    func apply(to nodes: [KnowledgeNode]) -> [KnowledgeNode] {
        nodes.filter { node in
            let matchesSearch = searchText.isEmpty
                || node.title.localizedCaseInsensitiveContains(searchText)
                || node.content.localizedCaseInsensitiveContains(searchText)
            let matchesType = types.isEmpty || types.contains(node.nodeType)
            return matchesSearch && matchesType
        }
    }
}
