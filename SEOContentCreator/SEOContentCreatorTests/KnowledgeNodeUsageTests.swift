import Testing
@testable import SEOContentCreator

struct KnowledgeNodeUsageTests {
    @Test func countsDirectionDoctorAndAttachedNodeUsage() {
        let direction = KnowledgeNode(title: "Онкология", type: .direction)
        let doctor = KnowledgeNode(title: "Доктор", type: .doctor)
        let fact = KnowledgeNode(title: "Факт", type: .fact)
        let a = Topic(title: "A", articleType: .disease, direction: direction)
        let b = Topic(title: "B", articleType: .disease, doctor: doctor)
        let c = Topic(title: "C", articleType: .disease)
        c.attachedNodes.append(fact)

        #expect(KnowledgeNodeUsage.count(for: direction, in: [a, b, c]) == 1)
        #expect(KnowledgeNodeUsage.count(for: doctor, in: [a, b, c]) == 1)
        #expect(KnowledgeNodeUsage.count(for: fact, in: [a, b, c]) == 1)
    }

    @Test func countsAdditionalDirections() throws {
        let node = KnowledgeNode(title: "Андрология", type: .direction)
        let topic = Topic(title: "Тема", articleType: .info)
        topic.additionalDirections = [node]
        #expect(KnowledgeNodeUsage.count(for: node, in: [topic]) == 1)
    }
}
