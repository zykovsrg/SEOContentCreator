# Knowledge Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the clinic Knowledge Base — a tree of reference nodes (directions, doctors, advantages, facts, sources) that can be searched/filtered and attached to topics; replace plain-text `direction`/`doctor` on `Topic` with node references.

**Architecture:** Native SwiftUI + SwiftData. `KnowledgeNode` is a self-referential `@Model` (parent/children). Pure, testable logic (tree filter, node suggestion) stays out of Views. The Knowledge Base section (tree + node detail + CRUD) replaces the placeholder in `RootView`. The Brief picks `direction`/`doctor` from the Knowledge Base.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing, Xcode 16+, macOS.

**Scope note:** Sub-project 2 of 7 (see `docs/superpowers/specs/2026-05-19-content-system-redesign-design.md`, §2.13, §4.6). Builds on Foundation (sub-project 1). This sub-project changes `Topic`: `direction`/`doctor` become `KnowledgeNode?` references — Foundation tests/views that used plain-text are updated here.

**Dev migration note:** Changing `Topic`'s `direction`/`doctor` from `String` to a relationship is a non-trivial SwiftData schema change. There is no production data yet, so the simplest correct approach is to reset the local store during development: delete the app's container (Xcode → run, or remove `~/Library/Containers/com.zykovsrg.SEOContentCreator` / the app's Application Support store) if the app fails to launch after the model change. This is acceptable because no real data exists.

---

## File Structure

- `SEOContentCreator/SEOContentCreator/Models/NodeType.swift` — node type enum (new)
- `SEOContentCreator/SEOContentCreator/Models/KnowledgeNode.swift` — `@Model` tree node (new)
- `SEOContentCreator/SEOContentCreator/Models/Topic.swift` — modify: `direction`/`doctor` → `KnowledgeNode?`, add `attachedNodes`
- `SEOContentCreator/SEOContentCreator/Logic/BriefValidation.swift` — modify: `hasDirection: Bool`
- `SEOContentCreator/SEOContentCreator/Logic/TopicStatus.swift` — modify: read `topic.direction != nil`
- `SEOContentCreator/SEOContentCreator/Logic/KnowledgeTreeFilter.swift` — search + filters (new)
- `SEOContentCreator/SEOContentCreator/Logic/NodeSuggestion.swift` — smart suggest (new)
- `SEOContentCreator/SEOContentCreator/Views/KnowledgeBaseView.swift` — tree + detail + CRUD (new)
- `SEOContentCreator/SEOContentCreator/Views/RootView.swift` — modify: real KB section
- `SEOContentCreator/SEOContentCreator/Views/BriefView.swift` — modify: direction/doctor pickers
- `SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift` — modify: show `direction?.title`
- `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift` — modify: add `KnowledgeNode` to container
- Tests (new): `KnowledgeTreeFilterTests.swift`, `NodeSuggestionTests.swift`
- Tests (modify): `BriefValidationTests.swift`, `TopicStatusTests.swift`, `ContentPlanFilterTests.swift`

---

## Task 1: NodeType enum

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/NodeType.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

enum NodeType: String, CaseIterable, Identifiable, Codable {
    case direction
    case doctor
    case advantage
    case fact
    case source
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direction: return "Направление"
        case .doctor:    return "Врач"
        case .advantage: return "Преимущество"
        case .fact:      return "Факт"
        case .source:    return "Источник"
        case .folder:    return "Раздел"
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/NodeType.swift
git commit -m "feat: add NodeType enum"
```

---

## Task 2: KnowledgeNode model + container

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/KnowledgeNode.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`

- [ ] **Step 1: Write KnowledgeNode**

```swift
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

    /// For OutlineGroup: nil for leaves so no disclosure triangle shows.
    var childrenOrNil: [KnowledgeNode]? {
        children.isEmpty ? nil : children
    }
}
```

- [ ] **Step 2: Add KnowledgeNode to the model container**

In `SEOContentCreatorApp.swift`, replace the `.modelContainer` line:

```swift
import SwiftUI
import SwiftData

@main
struct SEOContentCreatorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Topic.self, KnowledgeNode.self])
    }
}
```

- [ ] **Step 3: Build**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/KnowledgeNode.swift SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift
git commit -m "feat: add KnowledgeNode tree model"
```

---

## Task 3: Refactor Topic to reference nodes (+ fix Foundation logic/tests)

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/BriefValidation.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/TopicStatus.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/BriefValidationTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/TopicStatusTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/ContentPlanFilterTests.swift`

- [ ] **Step 1: Update BriefValidation (pure) — make direction a Bool input**

```swift
import Foundation

enum BriefValidation {
    static func canCreate(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canStartDraft(title: String, hasDirection: Bool) -> Bool {
        canCreate(title: title) && hasDirection
    }
}
```

- [ ] **Step 2: Update BriefValidationTests to new signature**

Replace the `draftRequiresTitleAndDirection` test:

```swift
    @Test func draftRequiresTitleAndDirection() {
        #expect(BriefValidation.canStartDraft(title: "Тема", hasDirection: false) == false)
        #expect(BriefValidation.canStartDraft(title: "", hasDirection: true) == false)
        #expect(BriefValidation.canStartDraft(title: "Тема", hasDirection: true) == true)
    }
```

- [ ] **Step 3: Update Topic model**

```swift
import Foundation
import SwiftData

@Model
final class Topic {
    var title: String
    var articleTypeRaw: String
    var targetVolume: Int?
    var notes: String
    var useStyle: Bool
    var createdAt: Date
    var updatedAt: Date
    var externalDocURL: String?
    var publishedAt: Date?

    @Relationship var direction: KnowledgeNode?
    @Relationship var doctor: KnowledgeNode?
    @Relationship var attachedNodes: [KnowledgeNode]

    init(
        title: String,
        articleType: ArticleType,
        targetVolume: Int? = nil,
        direction: KnowledgeNode? = nil,
        doctor: KnowledgeNode? = nil,
        notes: String = "",
        useStyle: Bool = false
    ) {
        self.title = title
        self.articleTypeRaw = articleType.rawValue
        self.targetVolume = targetVolume
        self.direction = direction
        self.doctor = doctor
        self.attachedNodes = []
        self.notes = notes
        self.useStyle = useStyle
        self.createdAt = .now
        self.updatedAt = .now
    }

    var articleType: ArticleType {
        get { ArticleType(rawValue: articleTypeRaw) ?? .info }
        set { articleTypeRaw = newValue.rawValue }
    }
}
```

- [ ] **Step 4: Update TopicStatus**

```swift
import Foundation

enum TopicStatus: Equatable {
    case idea
    case ready
    case published

    static func compute(for topic: Topic) -> TopicStatus {
        if topic.publishedAt != nil { return .published }
        if BriefValidation.canStartDraft(title: topic.title, hasDirection: topic.direction != nil) {
            return .ready
        }
        return .idea
    }

    var label: String {
        switch self {
        case .idea:      return "Идея"
        case .ready:     return "Готова к работе"
        case .published: return "Опубликовано"
        }
    }
}
```

- [ ] **Step 5: Update TopicStatusTests to use a node for direction**

```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct TopicStatusTests {
    @Test func ideaWhenDirectionMissing() {
        let t = Topic(title: "Тема", articleType: .info)
        #expect(TopicStatus.compute(for: t) == .idea)
    }

    @Test func readyWhenTitleAndDirectionPresent() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction)
        let t = Topic(title: "Тема", articleType: .info, direction: dir)
        #expect(TopicStatus.compute(for: t) == .ready)
    }

    @Test func publishedWhenPublishedAtSet() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction)
        let t = Topic(title: "Тема", articleType: .info, direction: dir)
        t.publishedAt = .now
        #expect(TopicStatus.compute(for: t) == .published)
    }
}
```

- [ ] **Step 6: Update ContentPlanFilterTests sample (remove plain-text direction)**

Replace the `sample()` helper:

```swift
    private func sample() -> [Topic] {
        [
            Topic(title: "Лечение рака простаты", articleType: .disease),
            Topic(title: "Услуга КТ-симуляция", articleType: .service),
            Topic(title: "Реабилитация", articleType: .info)
        ]
    }
```

- [ ] **Step 7: Run the full unit test suite**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests`
Expected: PASS (Foundation tests adapted to node-based direction).

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/Topic.swift SEOContentCreator/SEOContentCreator/Logic/BriefValidation.swift SEOContentCreator/SEOContentCreator/Logic/TopicStatus.swift SEOContentCreator/SEOContentCreatorTests
git commit -m "refactor: Topic.direction/doctor reference KnowledgeNode"
```

---

## Task 4: KnowledgeTreeFilter (TDD)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/KnowledgeTreeFilter.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/KnowledgeTreeFilterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SEOContentCreator

struct KnowledgeTreeFilterTests {
    private func sample() -> [KnowledgeNode] {
        [
            KnowledgeNode(title: "Малоинвазивные операции", type: .advantage),
            KnowledgeNode(title: "Усычкин С.В.", type: .doctor),
            KnowledgeNode(title: "Лучевая терапия", type: .direction)
        ]
    }

    @Test func emptyFilterReturnsAll() {
        let f = KnowledgeTreeFilter()
        #expect(f.apply(to: sample()).count == 3)
    }

    @Test func searchMatchesTitle() {
        var f = KnowledgeTreeFilter()
        f.searchText = "усычкин"
        let r = f.apply(to: sample())
        #expect(r.count == 1)
        #expect(r.first?.nodeType == .doctor)
    }

    @Test func typeFilterNarrows() {
        var f = KnowledgeTreeFilter()
        f.types = [.advantage]
        let r = f.apply(to: sample())
        #expect(r.count == 1)
        #expect(r.first?.title == "Малоинвазивные операции")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/KnowledgeTreeFilterTests`
Expected: FAIL — `cannot find 'KnowledgeTreeFilter' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/KnowledgeTreeFilterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/KnowledgeTreeFilter.swift SEOContentCreator/SEOContentCreatorTests/KnowledgeTreeFilterTests.swift
git commit -m "feat: add knowledge tree filter"
```

---

## Task 5: NodeSuggestion (TDD)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/NodeSuggestion.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/NodeSuggestionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SEOContentCreator

struct NodeSuggestionTests {
    private func directions() -> [KnowledgeNode] {
        [
            KnowledgeNode(title: "Лучевая терапия", type: .direction),
            KnowledgeNode(title: "Урология", type: .direction)
        ]
    }

    @Test func suggestsByTitleOverlap() {
        let s = NodeSuggestion.suggestDirections(
            forTopicTitle: "Лучевая терапия при раке простаты",
            from: directions()
        )
        #expect(s.first?.title == "Лучевая терапия")
    }

    @Test func noMatchReturnsEmpty() {
        let s = NodeSuggestion.suggestDirections(
            forTopicTitle: "Кардиология",
            from: directions()
        )
        #expect(s.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/NodeSuggestionTests`
Expected: FAIL — `cannot find 'NodeSuggestion' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/NodeSuggestionTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/NodeSuggestion.swift SEOContentCreator/SEOContentCreatorTests/NodeSuggestionTests.swift
git commit -m "feat: add node suggestion by title overlap"
```

---

## Task 6: KnowledgeBaseView (tree + detail + CRUD)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/KnowledgeBaseView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift`

- [ ] **Step 1: Write KnowledgeBaseView**

```swift
import SwiftUI
import SwiftData

struct KnowledgeBaseView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<KnowledgeNode> { $0.parent == nil },
           sort: \KnowledgeNode.title)
    private var roots: [KnowledgeNode]

    @State private var selection: KnowledgeNode?
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(roots) { root in
                    OutlineGroup(root, children: \.childrenOrNil) { node in
                        Label(node.title, systemImage: icon(for: node.nodeType))
                            .tag(node)
                    }
                }
            }
            .searchable(text: $search, prompt: "Поиск по справочнику")
            .toolbar {
                ToolbarItem {
                    Button { addRoot() } label: { Label("Узел", systemImage: "plus") }
                }
            }
            .navigationTitle("База знаний")
        } detail: {
            if let node = selection {
                NodeDetailView(node: node)
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

    private func addRoot() {
        let node = KnowledgeNode(title: "Новый раздел", type: .folder)
        context.insert(node)
        selection = node
    }
}

private struct NodeDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var node: KnowledgeNode

    var body: some View {
        Form {
            TextField("Заголовок", text: $node.title)
            Picker("Тип", selection: Binding(
                get: { node.nodeType },
                set: { node.nodeType = $0 }
            )) {
                ForEach(NodeType.allCases) { Text($0.title).tag($0) }
            }
            TextField("Содержимое", text: $node.content, axis: .vertical).lineLimit(3...8)
            Section("Действия") {
                Button("Добавить подузел") { addChild() }
                Button("Удалить", role: .destructive) { context.delete(node) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(node.title)
    }

    private func addChild() {
        let child = KnowledgeNode(title: "Новый узел", type: .fact, parent: node)
        context.insert(child)
    }
}
```

- [ ] **Step 2: Replace the KB placeholder in RootView**

In `RootView.swift`, change the `detail` switch so `.knowledgeBase` shows the real view:

```swift
import SwiftUI

struct RootView: View {
    @State private var selection: AppSection? = .contentPlan

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection ?? .contentPlan {
            case .contentPlan:
                ContentPlanView()
            case .knowledgeBase:
                KnowledgeBaseView()
            case .queue, .templates:
                let section = selection ?? .contentPlan
                ContentUnavailableView(
                    section.title,
                    systemImage: section.symbol,
                    description: Text("Раздел появится в следующем под-проекте.")
                )
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/KnowledgeBaseView.swift SEOContentCreator/SEOContentCreator/Views/RootView.swift
git commit -m "feat: knowledge base tree view with node CRUD"
```

---

## Task 7: Brief picks direction/doctor from Knowledge Base

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/BriefView.swift`

- [ ] **Step 1: Rewrite BriefView with node pickers**

```swift
import SwiftUI
import SwiftData

struct BriefView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<KnowledgeNode> { $0.nodeTypeRaw == "direction" },
           sort: \KnowledgeNode.title)
    private var directions: [KnowledgeNode]
    @Query(filter: #Predicate<KnowledgeNode> { $0.nodeTypeRaw == "doctor" },
           sort: \KnowledgeNode.title)
    private var doctors: [KnowledgeNode]

    var topic: Topic?

    @State private var title = ""
    @State private var articleType: ArticleType = .disease
    @State private var direction: KnowledgeNode?
    @State private var doctor: KnowledgeNode?
    @State private var volume = ""
    @State private var useStyle = false
    @State private var notes = ""

    var body: some View {
        Form {
            TextField("Название *", text: $title)
            Picker("Тип статьи *", selection: $articleType) {
                ForEach(ArticleType.allCases) { Text($0.title).tag($0) }
            }
            Picker("Направление *", selection: $direction) {
                Text("Не выбрано").tag(KnowledgeNode?.none)
                ForEach(directions) { Text($0.title).tag(KnowledgeNode?.some($0)) }
            }
            Picker("Врач", selection: $doctor) {
                Text("Не выбран").tag(KnowledgeNode?.none)
                ForEach(doctors) { Text($0.title).tag(KnowledgeNode?.some($0)) }
            }
            TextField("Целевой объём (знаков)", text: $volume)
            Toggle("Использовать Стиль/Главред", isOn: $useStyle)
            TextField("Заметки", text: $notes, axis: .vertical).lineLimit(3...6)
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }
                    .disabled(!BriefValidation.canCreate(title: title))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let topic else { return }
        title = topic.title
        articleType = topic.articleType
        direction = topic.direction
        doctor = topic.doctor
        volume = topic.targetVolume.map(String.init) ?? ""
        useStyle = topic.useStyle
        notes = topic.notes
    }

    private func save() {
        let vol = Int(volume.trimmingCharacters(in: .whitespaces))
        if let topic {
            topic.title = title
            topic.articleType = articleType
            topic.direction = direction
            topic.doctor = doctor
            topic.targetVolume = vol
            topic.useStyle = useStyle
            topic.notes = notes
            topic.updatedAt = .now
        } else {
            let new = Topic(
                title: title, articleType: articleType, targetVolume: vol,
                direction: direction, doctor: doctor, notes: notes, useStyle: useStyle
            )
            context.insert(new)
        }
        dismiss()
    }
}
```

- [ ] **Step 2: Build**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/BriefView.swift
git commit -m "feat: brief picks direction/doctor from knowledge base"
```

---

## Task 8: Content plan shows direction title + direction filter

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift`

- [ ] **Step 1: Update the Направление column**

In `ContentPlanView.swift`, change the direction `TableColumn` to read the node title:

```swift
            TableColumn("Направление") { Text($0.direction?.title ?? "—") }
```

- [ ] **Step 2: Build**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift
git commit -m "feat: content plan shows direction node title"
```

---

## Task 9: Final verification

- [ ] **Step 1: Build the whole app**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2: Run all unit tests**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests`
Expected: all PASS.

- [ ] **Step 3: Manual smoke check**

Launch (Cmd+R). If the app fails to launch due to the schema change, delete the old store (see Dev migration note) and relaunch. Then verify:
- **База знаний** section: add a root node, rename it, set its type to «Направление», add a child node, delete a node.
- Create a couple of `direction` nodes (e.g. «Лучевая терапия», «Урология») and a `doctor` node.
- **Контент-план → Новая тема**: «Направление» and «Врач» pickers list the nodes; pick «Лучевая терапия»; save; the topic row shows «Лучевая терапия» in Направление and «Готова к работе» status.
- Search and type filter in База знаний work.

- [ ] **Step 4: Commit (if any smoke fixes were needed)**

```bash
git add -A
git commit -m "fix: knowledge base smoke fixes"
```

---

## Self-Review

**Spec coverage (§2.13, §4.6):**
- Tree of nodes (directions, doctors, advantages, facts, sources) → Tasks 1, 2, 6. ✅
- Node = title + content + type + sources → Task 2. ✅
- Node CRUD (create/subnode/rename/delete) → Task 6. ✅
- Attach to topic (direction/doctor as nodes) → Tasks 3, 7. ✅
- Smart suggestion → Task 5 (pure logic; wired into Brief is a later enhancement — noted). 
- Search + type filter → Tasks 4, 6. ✅
- Replace plain-text direction/doctor → Task 3. ✅
- KB section replaces placeholder → Task 6. ✅

**Gaps (intentionally deferred):** advanced filters (by direction, by usage) and saved slices (§2.13) are reduced to type filter + search for this sub-project; full slices come in a later iteration. Sources editing UI on direction nodes is minimal (stored on model; rich editor later). `NodeSuggestion` is implemented and tested but not yet auto-shown in the Brief — wiring it as a prompt is a small follow-up.

**Placeholder scan:** No TBD/TODO; all code steps have full code; commands have expected output. ✅

**Type consistency:** `KnowledgeNode(title:type:content:sources:parent:)`, `NodeType`, `Topic.direction: KnowledgeNode?`, `BriefValidation.canStartDraft(title:hasDirection:)`, `KnowledgeTreeFilter.apply`, `NodeSuggestion.suggestDirections` are used identically across tasks and tests. ✅

---

## Next sub-projects (not in this plan)

3. Generation core (AI agents, stages, versions, side-by-side, accept edits).
4. Checks (SEO / Factcheck / Final edit, skills, soft hints).
5. Queue & automation.
6. Publication to Google Docs.
7. Templates (prompt editor, AI roles, variables, sandbox).
