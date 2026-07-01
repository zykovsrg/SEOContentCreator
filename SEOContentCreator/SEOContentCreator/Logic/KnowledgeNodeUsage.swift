enum KnowledgeNodeUsage {
    static func count(for node: KnowledgeNode, in topics: [Topic]) -> Int {
        topics.filter { topic in
            topic.direction === node
                || topic.doctor === node
                || topic.attachedNodes.contains(where: { $0 === node })
        }.count
    }
}
