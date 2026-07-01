import SwiftUI
import SwiftData

struct KnowledgeBaseView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \KnowledgeNode.title) private var allNodes: [KnowledgeNode]
    @Query(sort: \Topic.updatedAt, order: .reverse) private var topics: [Topic]

    @State private var selection: KnowledgeNode?
    @State private var search = ""

    private var roots: [KnowledgeNode] {
        allNodes.filter { $0.parent == nil }
    }

    private var searchResults: [KnowledgeNode] {
        var f = KnowledgeTreeFilter()
        f.searchText = search
        return f.apply(to: allNodes)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if search.isEmpty {
                    ForEach(roots) { root in
                        OutlineGroup(root, children: \.childrenOrNil) { node in
                            Label(node.title, systemImage: icon(for: node.nodeType))
                                .tag(node)
                        }
                    }
                } else {
                    ForEach(searchResults) { node in
                        Label(node.title, systemImage: icon(for: node.nodeType))
                            .tag(node)
                    }
                }
            }
            .searchable(text: $search, prompt: "Поиск по справочнику")
            .toolbar {
                ToolbarItem {
                    Menu {
                        ForEach(NodeType.allCases) { type in
                            Button(type.title) { addRoot(type: type) }
                        }
                    } label: {
                        Label("Узел", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("База знаний")
        } detail: {
            if let node = selection {
                NodeDetailView(node: node, topics: topics)
            } else {
                ContentUnavailableView("Выберите узел", systemImage: "books.vertical")
            }
        }
    }

    private func icon(for type: NodeType) -> String {
        switch type {
        case .direction: return "stethoscope"
        case .doctor:    return "person"
        case .advantage: return "star"
        case .fact:      return "checkmark.seal"
        case .source:    return "link"
        case .folder:    return "folder"
        }
    }

    private func addRoot(type: NodeType) {
        let node = KnowledgeNode(title: defaultTitle(for: type), type: type)
        context.insert(node)
        selection = node
    }

    private func defaultTitle(for type: NodeType) -> String {
        switch type {
        case .direction: return "Новое направление"
        case .doctor:    return "Новый врач"
        case .advantage: return "Новое преимущество"
        case .fact:      return "Новый факт"
        case .source:    return "Новый источник"
        case .folder:    return "Новый раздел"
        }
    }
}

private struct NodeDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var node: KnowledgeNode
    let topics: [Topic]
    @State private var confirmDelete = false

    private var usageCount: Int {
        KnowledgeNodeUsage.count(for: node, in: topics)
    }

    var body: some View {
        Form {
            TextField("Заголовок", text: $node.title)
            LabeledContent("Тип") {
                Menu(node.nodeType.title) {
                    ForEach(NodeType.allCases) { type in
                        Button(type.title) { node.nodeType = type }
                    }
                }
            }
            TextField("Содержимое", text: $node.content, axis: .vertical).lineLimit(3...8)
            Section("Действия") {
                Button("Добавить подузел") { addChild() }
                Button("Удалить", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(node.title)
        .confirmationDialog("Удалить узел базы знаний?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { context.delete(node) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(usageCount > 0
                 ? "Этот узел используется в \(usageCount) темах. После удаления брифы и промты могут потерять часть контекста."
                 : "Узел будет удалён из базы знаний.")
        }
    }

    private func addChild() {
        let child = node.addChild(title: "Новый узел", type: .fact)
        context.insert(child)
    }
}
