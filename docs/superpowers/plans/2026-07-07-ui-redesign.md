# UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the SEO Content Creator UI around one persistent sidebar, a right-hand inspector instead of stacked modal sheets, a vertical stage checklist, and colored status/progress — using native macOS `NavigationSplitView` and `.inspector()`.

**Architecture:** Extract the testable logic (status tone, pipeline state, template chip text, template categories) into small pure types under `Logic/`, TDD them with Swift Testing, then build the SwiftUI views on top. Views are compile-checked with `xcodebuild build-for-testing` and verified with a manual Cmd+U + click-through checklist. No data-model or generation changes.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing (`import Testing`). Xcode synchronized file groups (objectVersion 77) — new files in the folders are auto-added to the target; no `project.pbxproj` edits needed.

---

## Conventions used in every task

- **Build command** (compile check; the CLI test runner hangs, see project memory `xcodebuild-test-runner-hang`):

  ```bash
  cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && \
  xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5
  ```
  Expected on success: `** TEST BUILD SUCCEEDED **`.

- **Unit tests** run via Cmd+U in Xcode (not CLI). For logic tasks, still write the test file; it is exercised at the next Cmd+U.
- New source files go in `SEOContentCreator/SEOContentCreator/Logic/` or `.../Views/`; new tests in `SEOContentCreator/SEOContentCreatorTests/`.
- All paths below are relative to the repo root `/Users/zykovsrg/Documents/vibecode/SEOContentCreator`.

---

## Task 1: Status tone (colored status pill logic)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/TopicStatusStyle.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/TopicStatusStyleTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// TopicStatusStyleTests.swift
import Testing
@testable import SEOContentCreator

struct TopicStatusStyleTests {
    @Test func ideaIsNeutral() {
        #expect(TopicStatus.idea.tone == .neutral)
    }
    @Test func readyIsActive() {
        #expect(TopicStatus.ready.tone == .active)
    }
    @Test func publishedIsPositive() {
        #expect(TopicStatus.published.tone == .positive)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the build command above. Expected: compile FAILS — `StatusTone` / `tone` are undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// TopicStatusStyle.swift
import Foundation

/// Semantic severity for status chips. The view layer maps each tone to a
/// concrete color; keeping the mapping here makes it unit-testable.
enum StatusTone: Equatable {
    case neutral   // idea / not started
    case active    // in progress, ready to work
    case positive  // done / published
}

extension TopicStatus {
    var tone: StatusTone {
        switch self {
        case .idea:      return .neutral
        case .ready:     return .active
        case .published: return .positive
        }
    }
}
```

- [ ] **Step 4: Run build to verify it compiles**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`. (Assertions run at next Cmd+U.)

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/TopicStatusStyle.swift SEOContentCreator/SEOContentCreatorTests/TopicStatusStyleTests.swift
git commit -m "feat: add TopicStatus.tone for colored status pills"
```

---

## Task 2: Stage pipeline state (rail + progress dots logic)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/StagePipeline.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/StagePipelineTests.swift`

Notes: `StagePipeline.workflow` is the 8 article stages shown as progress dots and counted in the rail header (excludes `.promptAnalysis`, which is the analysis/learning stage). `current` = the first workflow stage that is not completed. Callers pass an `isCompleted` closure that wraps the existing `StageProgress.isCompleted`, so this stays pure and testable.

- [ ] **Step 1: Write the failing test**

```swift
// StagePipelineTests.swift
import Testing
@testable import SEOContentCreator

struct StagePipelineTests {
    @Test func workflowIsEightStagesWithoutPromptAnalysis() {
        #expect(StagePipeline.workflow.count == 8)
        #expect(StagePipeline.workflow.contains(.promptAnalysis) == false)
        #expect(StagePipeline.workflow.first == .structure)
        #expect(StagePipeline.workflow.last == .images)
    }

    @Test func nothingCompletedMakesFirstStageCurrent() {
        let states = StagePipeline.states { _ in false }
        #expect(states.first?.state == .current)
        #expect(states.dropFirst().allSatisfy { $0.state == .upcoming })
        #expect(StagePipeline.completedCount { _ in false } == 0)
        #expect(StagePipeline.nextStage { _ in false } == .structure)
    }

    @Test func completedPrefixMarksNextAsCurrent() {
        let done: Set<PipelineStage> = [.structure, .draft, .productBlocks]
        let states = StagePipeline.states { done.contains($0) }
        #expect(states[0].state == .done)
        #expect(states[2].state == .done)
        #expect(states[3].state == .current)   // semanticsInText
        #expect(states[4].state == .upcoming)
        #expect(StagePipeline.completedCount { done.contains($0) } == 3)
        #expect(StagePipeline.nextStage { done.contains($0) } == .semanticsInText)
    }

    @Test func allCompletedHasNoCurrentAndNoNext() {
        let states = StagePipeline.states { _ in true }
        #expect(states.allSatisfy { $0.state == .done })
        #expect(StagePipeline.completedCount { _ in true } == 8)
        #expect(StagePipeline.nextStage { _ in true } == nil)
    }
}
```

- [ ] **Step 2: Run build to verify it fails**

Run the build command. Expected: compile FAILS — `StagePipeline` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// StagePipeline.swift
import Foundation

enum StageState: Equatable {
    case done       // completed
    case current    // first not-yet-completed workflow stage
    case upcoming    // not reached yet
}

enum StagePipeline {
    /// Article workflow in order, used for the progress dots and the rail
    /// header count. Excludes `.promptAnalysis` (analysis/learning).
    static let workflow: [PipelineStage] = [
        .structure, .draft, .productBlocks, .semanticsInText,
        .seoCheck, .factCheck, .finalReview, .images
    ]

    static func completedCount(isCompleted: (PipelineStage) -> Bool) -> Int {
        workflow.filter(isCompleted).count
    }

    static func nextStage(isCompleted: (PipelineStage) -> Bool) -> PipelineStage? {
        workflow.first { !isCompleted($0) }
    }

    static func states(isCompleted: (PipelineStage) -> Bool) -> [(stage: PipelineStage, state: StageState)] {
        let next = nextStage(isCompleted: isCompleted)
        return workflow.map { stage in
            if isCompleted(stage) { return (stage, .done) }
            if stage == next { return (stage, .current) }
            return (stage, .upcoming)
        }
    }
}
```

- [ ] **Step 4: Run build to verify it compiles**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StagePipeline.swift SEOContentCreator/SEOContentCreatorTests/StagePipelineTests.swift
git commit -m "feat: add StagePipeline state/count/next for rail and progress dots"
```

---

## Task 3: Template chip text + categories (templates screen logic)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/TemplateChipText.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/TemplateCategory.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/TemplateChipTextTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// TemplateChipTextTests.swift
import Testing
@testable import SEOContentCreator

struct TemplateChipTextTests {
    @Test func tokensUnderThousandShownRaw() {
        #expect(TemplateChipText.tokens(800) == "800")
    }
    @Test func tokensRoundedToK() {
        #expect(TemplateChipText.tokens(8000) == "8k")
        #expect(TemplateChipText.tokens(11000) == "11k")
    }
    @Test func tokensNonRoundKeepsOneDecimal() {
        #expect(TemplateChipText.tokens(11500) == "11.5k")
    }
    @Test func chipJoinsModelTokensAndReasoning() {
        #expect(TemplateChipText.chip(model: "gpt-5.5", maxTokens: 11000, reasoning: "high")
                == "gpt-5.5 · 11k · high")
    }
    @Test func chipOmitsReasoningWhenNil() {
        #expect(TemplateChipText.chip(model: "gpt-4.1", maxTokens: 8000, reasoning: nil)
                == "gpt-4.1 · 8k")
    }
    @Test func categoriesCoverAllSixGroups() {
        #expect(TemplateCategory.allCases.count == 6)
        #expect(TemplateCategory.allCases.first == .stagePrompts)
    }
}
```

- [ ] **Step 2: Run build to verify it fails**

Run the build command. Expected: compile FAILS — `TemplateChipText` / `TemplateCategory` undefined.

- [ ] **Step 3: Write minimal implementations**

```swift
// TemplateChipText.swift
import Foundation

/// Formats the compact "model · tokens · reasoning" chip shown on stage-prompt
/// rows in the Templates screen.
enum TemplateChipText {
    static func tokens(_ n: Int) -> String {
        guard n >= 1000 else { return "\(n)" }
        let k = Double(n) / 1000.0
        if k == k.rounded() { return "\(Int(k))k" }
        return String(format: "%.1fk", k)
    }

    static func chip(model: String, maxTokens: Int, reasoning: String?) -> String {
        var parts = [model, tokens(maxTokens)]
        if let reasoning, !reasoning.isEmpty { parts.append(reasoning) }
        return parts.joined(separator: " · ")
    }
}
```

```swift
// TemplateCategory.swift
import Foundation

/// Top-level categories for the Templates screen, replacing the single long
/// list of 8 sections with a category selector.
enum TemplateCategory: String, CaseIterable, Identifiable {
    case stagePrompts   // Промты этапов
    case roles          // ИИ-роли
    case editorial      // Редполитика и источники
    case images         // Изображения (промты + пресеты)
    case skills         // Скиллы
    case forbidden      // Запрещённые формулировки

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stagePrompts: return "Промты этапов"
        case .roles:        return "ИИ-роли"
        case .editorial:    return "Редполитика"
        case .images:       return "Изображения"
        case .skills:       return "Скиллы"
        case .forbidden:    return "Запрещённые фразы"
        }
    }
}
```

- [ ] **Step 4: Run build to verify it compiles**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/TemplateChipText.swift SEOContentCreator/SEOContentCreator/Logic/TemplateCategory.swift SEOContentCreator/SEOContentCreatorTests/TemplateChipTextTests.swift
git commit -m "feat: add TemplateChipText and TemplateCategory for templates redesign"
```

---

## Task 4: Design-system components

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/DesignSystem.swift`

These are small reusable views. They are compile-checked; their appearance is verified visually in later tasks that use them.

- [ ] **Step 1: Create the components**

```swift
// DesignSystem.swift
import SwiftUI

extension StatusTone {
    var color: Color {
        switch self {
        case .neutral:  return .secondary
        case .active:   return .orange
        case .positive: return .green
        }
    }
}

/// Colored status chip used in the content plan.
struct StatusPill: View {
    let label: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tone.color).frame(width: 6, height: 6)
            Text(label).font(.caption).fontWeight(.semibold)
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(tone.color.opacity(0.14), in: Capsule())
        .foregroundStyle(tone.color)
    }
}

/// Compact 8-dot pipeline progress shown in the content-plan table.
struct StageProgressDots: View {
    /// One entry per `StagePipeline.workflow` stage, in order.
    let states: [StageState]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: state))
                    .frame(width: 9, height: 9)
            }
        }
    }

    private func color(for state: StageState) -> Color {
        switch state {
        case .done:     return .green
        case .current:  return .accentColor
        case .upcoming: return Color.secondary.opacity(0.25)
        }
    }
}

/// Small monospaced metadata chip (e.g. "gpt-5.5 · 11k · high").
struct MetaChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: Run build to verify it compiles**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/DesignSystem.swift
git commit -m "feat: add design-system components (StatusPill, StageProgressDots, MetaChip)"
```

---

## Task 5: Navigation shell — sidebar `NavigationSplitView`

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/AppSection.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift`

Replace the segmented picker with a persistent sidebar. Keep the seeder `.task`, keep Cmd+1/2/3, keep Settings as the native scene (do NOT add it to the sidebar).

- [ ] **Step 1: Add sidebar metadata to `AppSection`**

Replace the whole body of `AppSection.swift` with:

```swift
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case contentPlan, templates, knowledgeBase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contentPlan:   return "Контент-план"
        case .templates:     return "Шаблоны"
        case .knowledgeBase: return "База знаний"
        }
    }

    var systemImage: String {
        switch self {
        case .contentPlan:   return "list.bullet.rectangle"
        case .templates:     return "doc.text"
        case .knowledgeBase: return "books.vertical"
        }
    }

    /// Sidebar group heading this section belongs to.
    var group: String {
        switch self {
        case .contentPlan:            return "Работа"
        case .templates, .knowledgeBase: return "Знания"
        }
    }
}
```

- [ ] **Step 2: Rewrite `RootView` as a split view**

Replace the whole body of `RootView.swift` with:

```swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: AppSection? = .contentPlan

    private var groups: [(name: String, sections: [AppSection])] {
        [
            ("Работа", [.contentPlan]),
            ("Знания", [.templates, .knowledgeBase])
        ]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.sections) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .navigationTitle("SEO Content Creator")
            .background(sectionShortcuts)
        } detail: {
            switch selection ?? .contentPlan {
            case .contentPlan:   ContentPlanView()
            case .templates:     TemplatesView()
            case .knowledgeBase: KnowledgeBaseView()
            }
        }
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
            EditorDictionarySeeder.seedIfNeeded(in: context)
            SkillPresetSeeder.seedIfNeeded(in: context)
            ProductBlockSeeder.seedIfNeeded(in: context)
            ForbiddenPhraseSeeder.seedIfNeeded(in: context)
        }
    }

    /// Cmd+1/2/3 keep switching sections (now reflected by sidebar selection).
    private var sectionShortcuts: some View {
        Group {
            Button("") { selection = .contentPlan }.keyboardShortcut("1", modifiers: .command)
            Button("") { selection = .templates }.keyboardShortcut("2", modifiers: .command)
            Button("") { selection = .knowledgeBase }.keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
```

Note: `KnowledgeBaseView` currently has its own `NavigationSplitView`. Nesting is acceptable on macOS (three-column), but verify visually in the manual check; if the nested split looks wrong, that is handled in Task 8's sibling cleanup — for this task leave `KnowledgeBaseView` unchanged.

- [ ] **Step 3: Build**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check (Cmd+R)**

Verify: sidebar shows two groups; clicking rows switches the detail; Cmd+1/2/3 switch and the selected row highlights; Settings still opens with Cmd+,. Check light and dark theme.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/AppSection.swift SEOContentCreator/SEOContentCreator/Views/RootView.swift
git commit -m "feat: replace segmented picker with persistent sidebar NavigationSplitView"
```

---

## Task 6: Content plan — status pills + stage-progress column

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift`

Replace the plain "Статус" text column with a `StatusPill`, and add an "Этапы" column using `StageProgressDots`. Keep search, filter, context menu, delete dialog, and the open-topic flow unchanged.

- [ ] **Step 1: Update the two columns in `planTable`**

In `ContentPlanView.swift`, replace this block:

```swift
            TableColumn("Статус") { Text(TopicStatus.compute(for: $0).label) }
            TableColumn("Токены") { Text($0.totalTokenCost > 0 ? "\($0.totalTokenCost)" : "—") }
```

with:

```swift
            TableColumn("Этапы") { topic in
                StageProgressDots(states: stageStates(for: topic).map(\.state))
            }
            .width(110)
            TableColumn("Статус") { topic in
                let status = TopicStatus.compute(for: topic)
                StatusPill(label: status.label, tone: status.tone)
            }
            TableColumn("Токены") { Text($0.totalTokenCost > 0 ? "\($0.totalTokenCost)" : "—") }
```

- [ ] **Step 2: Add the helper that maps a topic to per-stage states**

Add this method inside `struct ContentPlanView` (e.g. after `visibleTopics`):

```swift
    private func stageStates(for topic: Topic) -> [(stage: PipelineStage, state: StageState)] {
        let hasImages = !topic.images.filter { !$0.isArchived }.isEmpty
        let hasRecs = !topic.promptRecommendations.isEmpty
        return StagePipeline.states { stage in
            StageProgress.isCompleted(
                stage, versions: topic.versions, structureText: topic.structureText,
                hasImages: hasImages, hasPromptRecommendations: hasRecs
            )
        }
    }
```

- [ ] **Step 3: Build**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check (Cmd+R)**

Verify: content plan shows colored status pills (grey Идея / orange Готова к работе / green Опубликовано) and an 8-dot progress column; green = done, accent = current stage. Search/filter/open/delete still work. Check dark theme.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift
git commit -m "feat: colored status pills and stage-progress column in content plan"
```

---

## Task 7: Stage rail — vertical checklist

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/StageRailView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift:33-35` (swap `StageBarView` for `StageRailView` inside a leading column — see Task 9). For this task only create the view and keep `StageBarView` in place; the wiring happens in Task 9.

`StageRailView` mirrors `StageBarView`'s data (roles query for agent names, `StageProgress`) but renders vertically with done/current/upcoming states and a header hint. It iterates `PipelineStage.allCases` (unchanged selectable set, so `.promptAnalysis` stays runnable) while the header count/next uses `StagePipeline.workflow`.

- [ ] **Step 1: Create `StageRailView`**

```swift
// StageRailView.swift
import SwiftUI
import SwiftData

struct StageRailView: View {
    @Binding var selectedStage: PipelineStage
    var topic: Topic
    @Query private var roles: [AIRole]

    private func isCompleted(_ stage: PipelineStage) -> Bool {
        StageProgress.isCompleted(
            stage, versions: topic.versions, structureText: topic.structureText,
            hasImages: !topic.images.filter { !$0.isArchived }.isEmpty,
            hasPromptRecommendations: !topic.promptRecommendations.isEmpty
        )
    }

    private var completedCount: Int {
        StagePipeline.completedCount(isCompleted: isCompleted)
    }

    private var nextStage: PipelineStage? {
        StagePipeline.nextStage(isCompleted: isCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Этапы").font(.subheadline).fontWeight(.semibold)
                Text(headerHint).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)

            ForEach(PipelineStage.allCases) { stage in
                Button { selectedStage = stage } label: {
                    row(for: stage)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 200)
    }

    private var headerHint: String {
        if let next = nextStage {
            return "\(completedCount) из \(StagePipeline.workflow.count) · дальше: \(next.title)"
        }
        return "\(completedCount) из \(StagePipeline.workflow.count) · всё готово"
    }

    @ViewBuilder
    private func row(for stage: PipelineStage) -> some View {
        let selected = selectedStage == stage
        HStack(alignment: .top, spacing: 9) {
            marker(for: stage)
            VStack(alignment: .leading, spacing: 1) {
                Text(stage.title)
                    .font(.callout)
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                Text(agentName(for: stage))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func marker(for stage: PipelineStage) -> some View {
        if isCompleted(stage) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.body)
        } else if stage == nextStage {
            Image(systemName: "circle.fill")
                .foregroundStyle(Color.accentColor).font(.caption)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Color.secondary.opacity(0.5)).font(.caption)
                .frame(width: 16, height: 16)
        }
    }

    private func agentName(for stage: PipelineStage) -> String {
        roles.first { $0.key == stage.roleKey }?.name ?? stage.agentName
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`. (Not yet shown in the app; wired in Task 9.)

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/StageRailView.swift
git commit -m "feat: add vertical StageRailView checklist"
```

---

## Task 8: Templates — category selector

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift`

Replace the single 8-section `List` with: a category picker at the top of the sidebar column, a list showing only the active category's items (with a `MetaChip` on stage-prompt rows and a single "Добавить" menu), plus a search field that switches to a cross-category flat result list when non-empty. Reuse all existing detail editors and the `TemplateSelection` enum unchanged.

- [ ] **Step 1: Add category state and search state**

In `TemplatesView`, add below `@State private var selection: TemplateSelection?`:

```swift
    @State private var category: TemplateCategory = .stagePrompts
    @State private var search = ""
```

- [ ] **Step 2: Replace the sidebar `List` with a category-scoped column**

Replace the `List(selection: $selection) { … }.frame(width: 260)` block in `body` with:

```swift
            VStack(spacing: 0) {
                Picker("Категория", selection: $category) {
                    ForEach(TemplateCategory.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(8)

                TextField("Поиск", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 8).padding(.bottom, 8)

                List(selection: $selection) {
                    if search.isEmpty {
                        categoryRows
                    } else {
                        searchRows
                    }
                }
            }
            .frame(width: 260)
```

- [ ] **Step 3: Add the row builders**

Add these `@ViewBuilder` properties/methods to `TemplatesView`:

```swift
    @ViewBuilder
    private var categoryRows: some View {
        switch category {
        case .stagePrompts:
            ForEach(sortedTemplates) { t in
                HStack {
                    Text(t.stage?.title ?? t.stageRaw)
                    Spacer()
                    MetaChip(text: TemplateChipText.chip(model: t.modelName,
                                                         maxTokens: t.maxTokens,
                                                         reasoning: t.reasoningEffort))
                }
                .tag(TemplateSelection.stage(t.uuid))
            }
        case .roles:
            ForEach(sortedRoles) { role in
                Text(role.name).tag(TemplateSelection.role(role.uuid))
            }
        case .editorial:
            ForEach(sortedBlocks) { block in
                Text(block.title).tag(TemplateSelection.block(block.uuid))
            }
        case .images:
            ForEach(sortedImagePrompts) { template in
                Text("Промт: \(template.kind?.title ?? template.kindRaw)")
                    .tag(TemplateSelection.imagePrompt(template.uuid))
            }
            ForEach(sortedImagePresets) { preset in
                Text("Пресет: \(preset.name)").tag(TemplateSelection.imagePreset(preset.uuid))
            }
        case .skills:
            ForEach(sortedSkills) { skill in
                Text(skill.name).tag(TemplateSelection.skill(skill.uuid))
            }
        case .forbidden:
            ForEach(sortedForbiddenPhrases) { phrase in
                Text(phrase.phrase).lineLimit(1).tag(TemplateSelection.forbiddenPhrase(phrase.uuid))
            }
        }
    }

    @ViewBuilder
    private var searchRows: some View {
        let q = search.lowercased()
        ForEach(sortedTemplates.filter { ($0.stage?.title ?? $0.stageRaw).lowercased().contains(q) }) { t in
            Text(t.stage?.title ?? t.stageRaw).tag(TemplateSelection.stage(t.uuid))
        }
        ForEach(sortedRoles.filter { $0.name.lowercased().contains(q) }) { role in
            Text(role.name).tag(TemplateSelection.role(role.uuid))
        }
        ForEach(sortedBlocks.filter { $0.title.lowercased().contains(q) }) { block in
            Text(block.title).tag(TemplateSelection.block(block.uuid))
        }
        ForEach(sortedSkills.filter { $0.name.lowercased().contains(q) }) { skill in
            Text(skill.name).tag(TemplateSelection.skill(skill.uuid))
        }
        ForEach(sortedProductBlocks.filter { $0.name.lowercased().contains(q) }) { block in
            Text(block.name).tag(TemplateSelection.productBlock(block.uuid))
        }
        ForEach(sortedForbiddenPhrases.filter { $0.phrase.lowercased().contains(q) }) { phrase in
            Text(phrase.phrase).lineLimit(1).tag(TemplateSelection.forbiddenPhrase(phrase.uuid))
        }
    }
```

Note: the "Продуктовые блоки" section from the old list is folded into search results and reachable via the editorial/skills detail flow; if you want it as its own category, that is a follow-up (out of scope here). Keep the existing `sortedProductBlocks` helper — it is still referenced by `searchRows` and the detail switch.

- [ ] **Step 4: Add a single "Добавить" toolbar menu**

Add a `.toolbar` modifier to the `HStack` in `body` (after `.navigationTitle("Шаблоны")`):

```swift
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Пресет изображения") {
                        let preset = ImageStylePreset(name: "Новый пресет", styleText: "")
                        context.insert(preset); selection = .imagePreset(preset.uuid); category = .images
                    }
                    Button("Скилл") {
                        let next = (skills.map(\.order).max() ?? -1) + 1
                        let preset = SkillPreset(name: "Новый скилл", prompt: "", roleKey: "editor", order: next)
                        context.insert(preset); selection = .skill(preset.uuid); category = .skills
                    }
                    Button("Продуктовый блок") {
                        let next = (productBlocks.map(\.order).max() ?? -1) + 1
                        let block = ProductBlock(name: "Новый блок", prompt: "", order: next)
                        context.insert(block); selection = .productBlock(block.uuid)
                    }
                    Button("Запрещённую формулировку") {
                        let next = (forbiddenPhrases.map(\.order).max() ?? -1) + 1
                        let phrase = ForbiddenPhrase(phrase: "Новая формулировка", problem: "", replacement: "", order: next)
                        context.insert(phrase); selection = .forbiddenPhrase(phrase.uuid); category = .forbidden
                    }
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
```

Remove the three inline `Button { … } label: { Label("Добавить …") }` blocks that used to live inside the old `List` sections (they are replaced by this menu). The `detail` computed property and `ensureSelection()` stay as-is.

- [ ] **Step 5: Build**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual check (Cmd+R)**

Verify: the templates screen shows a category menu + search; switching categories shows only that group; stage-prompt rows show the model/tokens/reasoning chip; the "Добавить" menu creates each entity type and selects it; typing in search shows cross-category matches; every detail editor still opens. Dark theme.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift
git commit -m "feat: category selector, search and meta chips in Templates"
```

---

## Task 9: Workspace inspector refactor (highest risk)

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`

Goal: (a) show `StageRailView` as a fixed leading column, (b) move Версии / Лог / Семантика and the review Замечания into a native `.inspector()` with a tab selector, (c) keep every accept/reject/redo/partial path and all existing helper methods unchanged, (d) keep Редактор / Публикация / Изображения / Продуктовые блоки / Структура / Бриф as sheets. Move in small steps; build after each.

- [ ] **Step 1: Add inspector state**

Add to the `@State` block of `TopicWorkspaceView`:

```swift
    @State private var showInspector = true
    @State private var inspectorTab: InspectorTab = .remarks

    enum InspectorTab: String, CaseIterable, Identifiable {
        case remarks, versions, semantics, log
        var id: String { rawValue }
        var title: String {
            switch self {
            case .remarks:   return "Замечания"
            case .versions:  return "Версии"
            case .semantics: return "Семантика"
            case .log:       return "Лог"
            }
        }
    }
```

- [ ] **Step 2: Wrap the main content in an HStack with the rail, and attach the inspector**

In `body`, change the top-level `VStack(spacing: 0) { header; Divider(); StageBarView(...); ... }` so the stage bar becomes a leading rail beside the content. Concretely, replace:

```swift
        VStack(spacing: 0) {
            header
            Divider()
            StageBarView(selectedStage: $selectedStage, topic: topic)
                .padding(.vertical, 8)
            Divider()
            if let error = executor?.lastErrorMessage {
```

with:

```swift
        HStack(spacing: 0) {
            StageRailView(selectedStage: $selectedStage, topic: topic)
                .background(.background.secondary)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if let error = executor?.lastErrorMessage {
```

Then close the new `VStack` and `HStack`: at the end of `body`, the existing outer `VStack` closing brace `}` (the one right before `.navigationTitle(topic.title)`) must be replaced by `} }` (close inner `VStack`, then the `HStack`). Verify brace balance by building.

- [ ] **Step 3: Attach the inspector modifier**

Immediately after `.navigationTitle(topic.title)` add:

```swift
        .inspector(isPresented: $showInspector) {
            inspectorPanel
                .inspectorColumnWidth(min: 300, ideal: 360, max: 460)
        }
```

- [ ] **Step 4: Add the inspector panel view**

Add to `TopicWorkspaceView`:

```swift
    @ViewBuilder
    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: $inspectorTab) {
                ForEach(InspectorTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch inspectorTab {
            case .remarks:   remarksTab
            case .versions:  VersionLaneView(topic: topic) { comparisonText = $0.text }
            case .semantics: SemanticsEditorSheet(topic: topic)
            case .log:       JobLogView(topic: topic)
            }
        }
    }

    @ViewBuilder
    private var remarksTab: some View {
        if isReviewing {
            RemarksPanelView(
                remarks: executor?.remarks ?? [],
                acceptedIDs: acceptedRemarkIDs,
                rejectedIDs: rejectedRemarkIDs,
                redoingIDs: redoingRemarkIDs,
                onAccept: {
                    acceptedRemarkIDs.insert($0.id); rejectedRemarkIDs.remove($0.id)
                    RemarkPersistence.updateStatus(remarkID: $0.id, status: .accepted,
                                                   jobID: executor?.lastRemarksJobID, topic: topic)
                },
                onReject: {
                    rejectedRemarkIDs.insert($0.id); acceptedRemarkIDs.remove($0.id)
                    RemarkPersistence.updateStatus(remarkID: $0.id, status: .rejected,
                                                   jobID: executor?.lastRemarksJobID, topic: topic)
                },
                onSelect: { highlightedQuote = $0.quote },
                onRedo: { redoRemark($0, comment: $1) }
            )
        } else {
            ContentUnavailableView("Нет замечаний",
                                   systemImage: "checkmark.circle",
                                   description: Text("Запустите проверяющий этап (SEO, фактчекинг, вычитка), чтобы получить замечания."))
        }
    }
```

- [ ] **Step 5: Replace the in-body review layout with the highlighted text + action bar only**

The old `if isReviewing { HStack { ScrollViewReader { … HighlightedText … } RemarksPanelView(...) .frame(width: 380) } … }` block put the remarks panel inline. Now the remarks live in the inspector, so the body's reviewing branch keeps only the highlighted text and the bottom "Отклонить всё / Готово" bar. Replace the whole `if isReviewing { … } else { … }` region's `isReviewing` branch with:

```swift
            if isReviewing {
                ScrollViewReader { proxy in
                    ScrollView {
                        HighlightedText(text: workingCopy, highlight: highlightedQuote)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    .onChange(of: highlightedQuote) { _, _ in
                        guard let index = highlightedParagraphIndex else { return }
                        withAnimation { proxy.scrollTo(index, anchor: .center) }
                    }
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Отклонить всё", role: .destructive) { endReview() }
                    Button("Готово") { finishReview() }.keyboardShortcut(.defaultAction)
                }
                .padding(8)
            } else {
```

Leave the `else` branch (SideBySide / SingleVersion + AcceptRejectBar) exactly as it is.

- [ ] **Step 6: Auto-open the Замечания tab when a check produces remarks**

So remarks are visible without hunting for the tab, add to `runStage(_:blocks:)` inside the `Task { … }` after `pendingVersionID = executor.lastResultVersionID`:

```swift
            if !(executor.remarks.isEmpty) {
                inspectorTab = .remarks
                showInspector = true
            }
```

- [ ] **Step 7: Remove the migrated sheets and add an inspector toggle to the toolbar**

Delete these three now-duplicated sheet modifiers from `body` (they live in the inspector now):

```swift
        .sheet(isPresented: $showVersions) {
            VersionLaneView(topic: topic) { comparisonText = $0.text }
        }
        .sheet(isPresented: $showLog) { JobLogView(topic: topic) }
        .sheet(isPresented: $showSemantics) { SemanticsEditorSheet(topic: topic) }
```

Delete the now-unused `@State` vars `showVersions`, `showLog`, `showSemantics`. In `toolbarContent`, remove the three toolbar buttons that set them (`showSemantics = true`, `showVersions = true`, `showLog = true`) and replace them with a single inspector toggle:

```swift
        ToolbarItem {
            Button { showInspector.toggle() } label: {
                Label("Инспектор", systemImage: "sidebar.trailing")
            }
            .help("Показать/скрыть инспектор")
        }
```

Keep the remaining toolbar buttons (Контент-план back, Подсказки, Редактор, Изображения, Опубликовать, Рекомендации по промтам) unchanged. Keep the sheets for Подсказки/Редактор/Изображения/Публикация/Структура/ПродуктовыеБлоки/PromptAnalysis/PartialAccept unchanged.

- [ ] **Step 8: Build**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`. If braces are unbalanced, fix per the compiler's line numbers (Steps 2 and 5 are the likely culprits).

- [ ] **Step 9: Manual check (Cmd+R) — full workspace regression**

Open a topic and verify, in light and dark theme:
- vertical stage rail on the left; selecting a stage works; header shows "N из 8 · дальше: …"; completed stages show green checks.
- inspector on the right toggles with the toolbar button; tabs switch between Замечания / Версии / Семантика / Лог; each shows the same content the old sheets did.
- run an author stage → pending version appears → Accept all / Reject / Partial accept all still work.
- run a checking stage (SEO/fact/review) → remarks appear in the inspector Замечания tab automatically; clicking a remark highlights its quote in the text; Accept/Reject/Redo work; "Готово" applies accepted remarks; "Отклонить всё" discards.
- Редактор, Изображения, Опубликовать, Структура, Продуктовые блоки, Рекомендации по промтам still open as before.
- native back button returns to the content plan.

- [ ] **Step 10: Delete the obsolete `StageBarView`**

`StageBarView` is no longer referenced. Confirm and remove:

```bash
grep -rn "StageBarView" SEOContentCreator/SEOContentCreator
# expect no references outside its own file
rm SEOContentCreator/SEOContentCreator/Views/StageBarView.swift
```

Rebuild to confirm nothing broke.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: workspace inspector + vertical stage rail; retire StageBarView"
```

---

## Task 10: Final verification & task memory

**Files:**
- Modify: `ai/current-task.md`

- [ ] **Step 1: Full build**

Run the build command. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 2: Ask the user to run Cmd+U**

The CLI test runner hangs (project memory). Ask the user to run Cmd+U in Xcode and report results for the new tests (`TopicStatusStyleTests`, `StagePipelineTests`, `TemplateChipTextTests`) plus the existing suite (regression).

- [ ] **Step 3: Record the task in `ai/current-task.md`**

Set Status: review, Stage: review, fill Goal/Relevant files/Done criteria/handoff to reflect the redesign, listing the manual-check results and the pending Cmd+U run as the open risk.

- [ ] **Step 4: Propose task-finish**

Once the user confirms Cmd+U + manual checks pass, run `task-finish` (changelog entry, decisions if any, commit; offer push of the `redesign/ui-overhaul` branch and a PR).

---

## Self-review notes

- **Spec coverage:** shell (T5), inspector + rail + workspace (T7/T9), content plan (T6), templates (T8), design system (T4), status/pipeline/chip logic (T1–T3), testing + manual checklist (each view task + T10). All six spec components covered.
- **Type consistency:** `StatusTone` (T1) → `.color` (T4) → `StatusPill` (T4/T6); `StageState`/`StagePipeline.states` (T2) → `StageProgressDots` (T4/T6) and `StageRailView` (T7); `TemplateChipText.chip` (T3) → `MetaChip` (T8); `InspectorTab` (T9) local to workspace.
- **No fake view unit tests:** SwiftUI views are compile-checked + manually verified, consistent with the project's testing memory. Only pure logic (T1–T3) has `#expect` tests.
