# Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the working skeleton of the macOS app — window, sidebar, data model (SwiftData), Content Plan (topic CRUD) and the Brief form. No AI in this sub-project.

**Architecture:** Native SwiftUI macOS app. `NavigationSplitView` (sidebar + detail). SwiftData for persistence. Pure, testable logic types (validation, filtering, status) live separately from Views and are covered by Swift Testing unit tests. Run via `xcodebuild`.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing, Xcode 16+, macOS.

> **Статус исполнения (2026-05-22):** все 9 задач реализованы, сборка и все unit-тесты зелёные. Правка по ходу: из `Topic` убрано явное поле `id` (для `@Model` используется `persistentModelID`). Осталась ручная smoke-проверка (запуск приложения).

**Scope note:** This is sub-project 1 of 7 (see `docs/superpowers/specs/2026-05-19-content-system-redesign-design.md`). No AI, no pipeline, no versions yet — only topic management. `direction`/`doctor` are plain text here; sub-project 2 (Knowledge Base) will replace them with node references.

---

## File Structure

- `SEOContentCreator/SEOContentCreatorApp.swift` — app entry, `ModelContainer`
- `SEOContentCreator/Models/ArticleType.swift` — article type enum
- `SEOContentCreator/Models/Topic.swift` — `@Model` Topic
- `SEOContentCreator/Logic/BriefValidation.swift` — brief field validation (pure)
- `SEOContentCreator/Logic/TopicStatus.swift` — computed status (pure)
- `SEOContentCreator/Logic/ContentPlanFilter.swift` — list filter/search (pure)
- `SEOContentCreator/Views/RootView.swift` — `NavigationSplitView`
- `SEOContentCreator/Views/SidebarView.swift` — sections list
- `SEOContentCreator/Views/ContentPlanView.swift` — topics table + filters
- `SEOContentCreator/Views/BriefView.swift` — create/edit topic form
- `SEOContentCreatorTests/BriefValidationTests.swift`
- `SEOContentCreatorTests/TopicStatusTests.swift`
- `SEOContentCreatorTests/ContentPlanFilterTests.swift`

Pure logic (validation, status, filter) is separated from Views so it can be unit-tested without UI.

---

## Task 1: Create Xcode project

**Files:** project scaffold (created by Xcode).

- [ ] **Step 1: Create the project (manual, in Xcode)**

In Xcode: File → New → Project → macOS → App. Product Name: `SEOContentCreator`. Interface: SwiftUI. Language: Swift. Storage: None (we add SwiftData manually). Include Tests: yes. Save into `/Users/zykovsrg/Documents/vibecode/SEOContentCreator/`.

Xcode 16 uses file-system synchronized groups: `.swift` files placed in the target folder are picked up automatically.

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator SEOContentCreator.xcodeproj SEOContentCreatorTests
git commit -m "chore: scaffold SwiftUI macOS app"
```

---

## Task 2: ArticleType enum

**Files:**
- Create: `SEOContentCreator/Models/ArticleType.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

enum ArticleType: String, CaseIterable, Identifiable, Codable {
    case disease
    case service
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disease: return "Заболевание"
        case .service:  return "Услуга"
        case .info:     return "Информационная"
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/Models/ArticleType.swift
git commit -m "feat: add ArticleType enum"
```

---

## Task 3: Topic model (SwiftData)

**Files:**
- Create: `SEOContentCreator/Models/Topic.swift`

- [ ] **Step 1: Write the model**

```swift
import Foundation
import SwiftData

@Model
final class Topic {
    var id: UUID
    var title: String
    var articleTypeRaw: String
    var targetVolume: Int?
    var direction: String   // plain text for now; becomes a Knowledge Base node in sub-project 2
    var doctor: String      // plain text for now
    var notes: String
    var useStyle: Bool
    var createdAt: Date
    var updatedAt: Date
    var externalDocURL: String?
    var publishedAt: Date?

    init(
        title: String,
        articleType: ArticleType,
        targetVolume: Int? = nil,
        direction: String = "",
        doctor: String = "",
        notes: String = "",
        useStyle: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.articleTypeRaw = articleType.rawValue
        self.targetVolume = targetVolume
        self.direction = direction
        self.doctor = doctor
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

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/Models/Topic.swift
git commit -m "feat: add Topic SwiftData model"
```

---

## Task 4: Brief validation (TDD)

**Files:**
- Create: `SEOContentCreator/Logic/BriefValidation.swift`
- Test: `SEOContentCreatorTests/BriefValidationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SEOContentCreator

struct BriefValidationTests {
    @Test func cannotCreateWithEmptyTitle() {
        #expect(BriefValidation.canCreate(title: "") == false)
        #expect(BriefValidation.canCreate(title: "   ") == false)
    }

    @Test func canCreateWithTitle() {
        #expect(BriefValidation.canCreate(title: "Рак простаты") == true)
    }

    @Test func draftRequiresTitleAndDirection() {
        #expect(BriefValidation.canStartDraft(title: "Тема", direction: "") == false)
        #expect(BriefValidation.canStartDraft(title: "", direction: "Лучевая терапия") == false)
        #expect(BriefValidation.canStartDraft(title: "Тема", direction: "Лучевая терапия") == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/BriefValidationTests`
Expected: FAIL — `cannot find 'BriefValidation' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

enum BriefValidation {
    static func canCreate(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canStartDraft(title: String, direction: String) -> Bool {
        canCreate(title: title)
        && !direction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/BriefValidationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/Logic/BriefValidation.swift SEOContentCreatorTests/BriefValidationTests.swift
git commit -m "feat: add brief validation"
```

---

## Task 5: Topic status (TDD)

**Files:**
- Create: `SEOContentCreator/Logic/TopicStatus.swift`
- Test: `SEOContentCreatorTests/TopicStatusTests.swift`

- [ ] **Step 1: Write the failing test**

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
        let t = Topic(title: "Тема", articleType: .info, direction: "Лучевая терапия")
        #expect(TopicStatus.compute(for: t) == .ready)
    }

    @Test func publishedWhenPublishedAtSet() {
        let t = Topic(title: "Тема", articleType: .info, direction: "Лучевая терапия")
        t.publishedAt = .now
        #expect(TopicStatus.compute(for: t) == .published)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/TopicStatusTests`
Expected: FAIL — `cannot find 'TopicStatus' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

enum TopicStatus: Equatable {
    case idea
    case ready
    case published

    static func compute(for topic: Topic) -> TopicStatus {
        if topic.publishedAt != nil { return .published }
        if BriefValidation.canStartDraft(title: topic.title, direction: topic.direction) {
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

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/TopicStatusTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/Logic/TopicStatus.swift SEOContentCreatorTests/TopicStatusTests.swift
git commit -m "feat: add computed topic status"
```

---

## Task 6: Content plan filter (TDD)

**Files:**
- Create: `SEOContentCreator/Logic/ContentPlanFilter.swift`
- Test: `SEOContentCreatorTests/ContentPlanFilterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SEOContentCreator

struct ContentPlanFilterTests {
    private func sample() -> [Topic] {
        [
            Topic(title: "Лечение рака простаты", articleType: .disease, direction: "Лучевая терапия"),
            Topic(title: "Услуга КТ-симуляция", articleType: .service, direction: "Лучевая терапия"),
            Topic(title: "Реабилитация", articleType: .info, direction: "")
        ]
    }

    @Test func emptyFilterReturnsAll() {
        let f = ContentPlanFilter()
        #expect(f.apply(to: sample()).count == 3)
    }

    @Test func searchMatchesTitleCaseInsensitive() {
        var f = ContentPlanFilter()
        f.searchText = "простаты"
        let result = f.apply(to: sample())
        #expect(result.count == 1)
        #expect(result.first?.title == "Лечение рака простаты")
    }

    @Test func typeFilterNarrows() {
        var f = ContentPlanFilter()
        f.type = .service
        let result = f.apply(to: sample())
        #expect(result.count == 1)
        #expect(result.first?.articleType == .service)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ContentPlanFilterTests`
Expected: FAIL — `cannot find 'ContentPlanFilter' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct ContentPlanFilter {
    var searchText: String = ""
    var type: ArticleType? = nil

    func apply(to topics: [Topic]) -> [Topic] {
        topics.filter { topic in
            let matchesSearch = searchText.isEmpty
                || topic.title.localizedCaseInsensitiveContains(searchText)
            let matchesType = type == nil || topic.articleType == type
            return matchesSearch && matchesType
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ContentPlanFilterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/Logic/ContentPlanFilter.swift SEOContentCreatorTests/ContentPlanFilterTests.swift
git commit -m "feat: add content plan filter"
```

---

## Task 7: App entry + ModelContainer

**Files:**
- Modify: `SEOContentCreator/SEOContentCreatorApp.swift`

- [ ] **Step 1: Replace the app entry**

```swift
import SwiftUI
import SwiftData

@main
struct SEOContentCreatorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Topic.self)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: FAIL — `cannot find 'RootView' in scope` (created in Task 8). This is expected; proceed.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreatorApp.swift
git commit -m "feat: wire ModelContainer for Topic"
```

---

## Task 8: RootView + Sidebar

**Files:**
- Create: `SEOContentCreator/Views/RootView.swift`
- Create: `SEOContentCreator/Views/SidebarView.swift`

- [ ] **Step 1: Write SidebarView**

```swift
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case contentPlan, queue, templates, knowledgeBase
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contentPlan:   return "Контент-план"
        case .queue:         return "Очередь"
        case .templates:     return "Шаблоны"
        case .knowledgeBase: return "База знаний"
        }
    }
    var symbol: String {
        switch self {
        case .contentPlan:   return "list.bullet.rectangle"
        case .queue:         return "clock"
        case .templates:     return "puzzlepiece"
        case .knowledgeBase: return "books.vertical"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: AppSection
    var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.symbol).tag(section)
        }
        .navigationTitle("SEOContentCreator")
    }
}
```

- [ ] **Step 2: Write RootView**

```swift
import SwiftUI

struct RootView: View {
    @State private var selection: AppSection = .contentPlan
    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
            case .contentPlan:
                ContentPlanView()
            case .queue, .templates, .knowledgeBase:
                ContentUnavailableView(
                    selection.title,
                    systemImage: selection.symbol,
                    description: Text("Раздел появится в следующем под-проекте.")
                )
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: FAIL — `cannot find 'ContentPlanView' in scope` (created in Task 9). Expected; proceed.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/Views/RootView.swift SEOContentCreator/Views/SidebarView.swift
git commit -m "feat: add root split view and sidebar"
```

---

## Task 9: ContentPlanView + BriefView (CRUD)

**Files:**
- Create: `SEOContentCreator/Views/ContentPlanView.swift`
- Create: `SEOContentCreator/Views/BriefView.swift`

- [ ] **Step 1: Write BriefView (create/edit form)**

```swift
import SwiftUI
import SwiftData

struct BriefView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Existing topic to edit, or nil to create a new one.
    var topic: Topic?

    @State private var title = ""
    @State private var articleType: ArticleType = .disease
    @State private var direction = ""
    @State private var doctor = ""
    @State private var volume = ""
    @State private var useStyle = false
    @State private var notes = ""

    var body: some View {
        Form {
            TextField("Название *", text: $title)
            Picker("Тип статьи *", selection: $articleType) {
                ForEach(ArticleType.allCases) { Text($0.title).tag($0) }
            }
            TextField("Направление", text: $direction)
            TextField("Врач", text: $doctor)
            TextField("Целевой объём (знаков)", text: $volume)
            Toggle("Использовать Стиль/Главред", isOn: $useStyle)
            TextField("Заметки", text: $notes, axis: .vertical).lineLimit(3...6)
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
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

- [ ] **Step 2: Write ContentPlanView (list + filters + create/delete)**

```swift
import SwiftUI
import SwiftData

struct ContentPlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.updatedAt, order: .reverse) private var topics: [Topic]

    @State private var filter = ContentPlanFilter()
    @State private var showingBrief = false
    @State private var editingTopic: Topic?

    private var visibleTopics: [Topic] { filter.apply(to: topics) }

    var body: some View {
        Table(visibleTopics) {
            TableColumn("Тема") { Text($0.title) }
            TableColumn("Тип") { Text($0.articleType.title) }
            TableColumn("Направление") { Text($0.direction.isEmpty ? "—" : $0.direction) }
            TableColumn("Статус") { Text(TopicStatus.compute(for: $0).label) }
        }
        .contextMenu(forSelectionType: Topic.ID.self) { ids in
            if let id = ids.first, let t = topics.first(where: { $0.id == id }) {
                Button("Редактировать") { editingTopic = t }
                Button("Удалить", role: .destructive) { context.delete(t) }
            }
        }
        .searchable(text: $filter.searchText, prompt: "Поиск по темам")
        .toolbar {
            ToolbarItem {
                Picker("Тип", selection: $filter.type) {
                    Text("Все типы").tag(ArticleType?.none)
                    ForEach(ArticleType.allCases) { Text($0.title).tag(ArticleType?.some($0)) }
                }
            }
            ToolbarItem {
                Button { showingBrief = true } label: { Label("Новая тема", systemImage: "plus") }
            }
        }
        .navigationTitle("Контент-план")
        .sheet(isPresented: $showingBrief) { BriefView(topic: nil) }
        .sheet(item: $editingTopic) { BriefView(topic: $0) }
    }
}
```

- [ ] **Step 3: Build the whole app**

Run: `xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED` (RootView/ContentPlanView/BriefView all resolve now).

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS'`
Expected: all tests PASS.

- [ ] **Step 5: Manual smoke check**

Launch the app from Xcode (Cmd+R). Verify: window opens with sidebar; click «Новая тема» → fill «Название» + «Направление» → Сохранить → topic appears in the table; right-click → Редактировать changes it; right-click → Удалить removes it; search and type filter work.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/Views/ContentPlanView.swift SEOContentCreator/Views/BriefView.swift
git commit -m "feat: content plan list and brief form (topic CRUD)"
```

---

## Self-Review

**Spec coverage (sub-project 1 = Foundation):**
- Window + sidebar with sections → Task 8 (RootView, SidebarView). ✅
- Data model (SwiftData) → Tasks 2–3 (ArticleType, Topic). ✅
- Content Plan: list, filters, search, create/edit/delete → Tasks 6, 9. ✅
- Brief form (name, type, direction, doctor, volume, style flag, notes) → Task 9. ✅
- Computed status → Task 5. ✅
- Out of scope here (later sub-projects): versions, pipeline, AI, knowledge base, queue, publication, templates. `direction`/`doctor` intentionally plain text for now.

**Placeholder scan:** No TBD/TODO; every code step has full code; commands have expected output. ✅

**Type consistency:** `Topic`, `ArticleType`, `BriefValidation.canCreate/canStartDraft`, `TopicStatus.compute`, `ContentPlanFilter.apply` are used with identical signatures across tasks and tests. ✅

**Note:** Tasks 7 and 8 intentionally build-fail in isolation because they reference types created in later tasks; the app fully builds at Task 9 Step 3. This is fine under sequential execution.

---

## Next sub-projects (not in this plan)

2. Knowledge Base (tree + node attach) → replaces plain-text `direction`/`doctor` with node references.
3. Generation core (AI agents, stages, versions, side-by-side, accept edits).
4. Checks (SEO / Factcheck / Final edit, skills, soft hints).
5. Queue & automation.
6. Publication to Google Docs.
7. Templates (prompt editor, AI roles, variables, sandbox).
