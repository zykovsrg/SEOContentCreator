# Reader Intent and Semantics Coordination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Задача читателя → Семантика` a clear, non-blocking preparation flow, open Semantics in a visible sheet, feed saved reader intent into semantic AI prompts, and keep reader-intent staleness correct after automatic collection.

**Architecture:** Introduce one small preparation-destination enum shared by the rail and workspace so order and presentation intent are testable without UI-inspection dependencies. Reuse `SemanticsEditorSheet` inside a dedicated modal wrapper, reuse `ReaderIntentPromptRenderer` in both semantic AI prompt builders, and synchronize the existing `semanticSnapshot` only after the collection pipeline has completed every external layer and merged survivors.

**Tech Stack:** Swift 6, SwiftUI for macOS, SwiftData, Swift Testing, Xcode `xcodebuild`.

## Global Constraints

- Preparation order is exactly `Задача читателя`, then `Семантика`.
- Missing reader intent warns but never disables Semantics or collection.
- Keep the existing Semantics inspector tab.
- Do not add or change SwiftData fields and do not add a migration.
- Do not change Wordstat region, device, threshold, top-100, funnel, or cannibalization defaults.
- Use the existing `ReaderIntentPromptRenderer`; do not duplicate reader-intent formatting.
- Refresh `semanticSnapshot` only after a successful coordinated automatic run.
- Later manual accepted/required query changes must still make reader intent stale.
- Add no new dependencies or test frameworks.
- Do not include the user's existing `project.pbxproj`, Xcode UI-state, `.claude/worktrees/`, or controlled-memory changes in implementation commits.

---

### Task 1: Testable preparation order and visible Semantics sheet

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/PreparationDestination.swift`
- Create: `SEOContentCreator/SEOContentCreator/Views/SemanticsWorkspaceSheet.swift`
- Create: `SEOContentCreator/SEOContentCreatorTests/PreparationDestinationTests.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/StageRailView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`

**Interfaces:**
- Produces: `enum PreparationDestination: String, CaseIterable, Identifiable`
- Produces: `PreparationDestination.allCases == [.readerIntent, .semantics]`
- Produces: `StageRailView.openPreparation: (PreparationDestination) -> Void`
- Produces: `SemanticsWorkspaceSheet(topic: Topic)`
- Consumes: existing `ReaderIntentStatus`, `ReaderIntentSheet`, and `SemanticsEditorSheet`

- [ ] **Step 1: Write the failing order test**

Create `PreparationDestinationTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct PreparationDestinationTests {
    @Test func readerIntentPrecedesSemantics() {
        #expect(PreparationDestination.allCases == [.readerIntent, .semantics])
    }

    @Test func destinationsKeepUserFacingTitles() {
        #expect(PreparationDestination.readerIntent.title == "Задача читателя")
        #expect(PreparationDestination.semantics.title == "Семантика")
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
cd SEOContentCreator
xcodebuild test \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationTask1 \
  -only-testing:SEOContentCreatorTests/PreparationDestinationTests
```

Expected: test build fails because `PreparationDestination` does not exist.

- [ ] **Step 3: Add the minimal shared destination type**

Create `PreparationDestination.swift`:

```swift
import Foundation

enum PreparationDestination: String, CaseIterable, Identifiable {
    case readerIntent
    case semantics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readerIntent: return "Задача читателя"
        case .semantics: return "Семантика"
        }
    }
}
```

- [ ] **Step 4: Render preparation rows from the shared order**

In `StageRailView`, replace the two callback properties with:

```swift
var openPreparation: (PreparationDestination) -> Void
```

Replace `preparationSection` with:

```swift
private var preparationSection: some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("Подготовка статьи")
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)

        ForEach(PreparationDestination.allCases) { destination in
            Button { openPreparation(destination) } label: {
                switch destination {
                case .readerIntent:
                    readerIntentRow
                case .semantics:
                    semanticsRow
                }
            }
            .buttonStyle(.plain)
        }
    }
}

@ViewBuilder
private var readerIntentRow: some View {
    switch ReaderIntentStatus.forTopic(topic) {
    case .missing:
        preparationRow(
            title: "Задача читателя", subtitle: "Не заполнена",
            icon: "circle", color: .secondary
        )
    case .ready(let summary):
        preparationRow(
            title: "Задача читателя", subtitle: "Готова · \(summary)",
            icon: "checkmark.circle.fill", color: .green
        )
    case .stale(let summary):
        preparationRow(
            title: "Задача читателя", subtitle: "Семантика изменилась · \(summary)",
            icon: "exclamationmark.triangle.fill", color: .orange
        )
    }
}

private var semanticsRow: some View {
    preparationRow(
        title: "Семантика",
        subtitle: topic.semanticKeywords.isEmpty
            ? "Не заполнена"
            : "Запросов: \(topic.semanticKeywords.count)",
        icon: topic.semanticKeywords.isEmpty ? "circle" : "checkmark.circle.fill",
        color: topic.semanticKeywords.isEmpty ? .secondary : .green
    )
}
```

Keep the existing `preparationRow` implementation unchanged.

- [ ] **Step 5: Add a dedicated reusable Semantics sheet**

Create `SemanticsWorkspaceSheet.swift`:

```swift
import SwiftUI

struct SemanticsWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    var body: some View {
        VStack(spacing: 0) {
            if topic.readerIntent == nil {
                Label(
                    "Задача читателя не заполнена. Семантику можно собрать, "
                    + "но оценка интересов и практической цели аудитории будет менее точной.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                Divider()
            }

            SemanticsEditorSheet(topic: topic)

            Divider()
            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 920, height: 720)
    }
}
```

This wrapper does not disable any control in `SemanticsEditorSheet`.

- [ ] **Step 6: Drive sheet presentation from the selected destination**

In `TopicWorkspaceView`, replace:

```swift
@State private var showReaderIntent = false
```

with:

```swift
@State private var preparationDestination: PreparationDestination?
```

Construct `StageRailView` with:

```swift
StageRailView(
    selectedStage: $selectedStage,
    topic: topic,
    openPreparation: { preparationDestination = $0 }
)
```

Replace the reader-intent sheet modifier with:

```swift
.sheet(item: $preparationDestination) { destination in
    switch destination {
    case .readerIntent:
        ReaderIntentSheet(topic: topic)
    case .semantics:
        SemanticsWorkspaceSheet(topic: topic)
    }
}
```

Keep `InspectorTab.semantics` and its `SemanticsEditorSheet(topic:)` branch
unchanged.

- [ ] **Step 7: Run Task 1 tests and build**

Run:

```bash
cd SEOContentCreator
xcodebuild test \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationTask1 \
  -only-testing:SEOContentCreatorTests/PreparationDestinationTests
```

Expected: `PreparationDestinationTests` passes.

Run:

```bash
cd SEOContentCreator
xcodebuild build-for-testing \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationTask1
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit Task 1 only**

```bash
git add \
  SEOContentCreator/SEOContentCreator/Logic/PreparationDestination.swift \
  SEOContentCreator/SEOContentCreator/Views/SemanticsWorkspaceSheet.swift \
  SEOContentCreator/SEOContentCreator/Views/StageRailView.swift \
  SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift \
  SEOContentCreator/SEOContentCreatorTests/PreparationDestinationTests.swift
git commit -m "fix: open coordinated preparation sheets"
```

Before committing, verify `git diff --cached --name-only` contains only these
five files.

---

### Task 2: Feed reader intent into semantic seed and relevance prompts

**Files:**
- Create: `SEOContentCreator/SEOContentCreatorTests/SemanticReaderIntentPromptTests.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticSeedPlanner.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift`

**Interfaces:**
- Consumes: `ReaderIntentPromptRenderer.render(topic:) -> String`
- Produces: `SemanticSeedPlanner.userPrompt(topic:masks:) -> String` with reader intent
- Produces: `SemanticAgentAnalyzer.userPrompt(topic:queries:) -> String` with reader intent

- [ ] **Step 1: Write failing prompt-context tests**

Create `SemanticReaderIntentPromptTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

@MainActor
struct SemanticReaderIntentPromptTests {
    private func topicWithIntent() -> Topic {
        let topic = Topic(title: "Манеж для шестимесячного ребёнка", articleType: .info)
        topic.readerIntent = ReaderIntent(
            query: "манеж для 6 месячного",
            audienceContext: "родитель ребёнка шести месяцев",
            hiddenGoal: "обеспечить безопасность и освободить руки",
            successCriterion: "ребёнок в безопасности, родитель может заниматься делами",
            barriers: "страх навредить развитию и ограниченное пространство",
            solutionType: .comparison,
            solutionFormat: "чек-лист критериев выбора"
        )
        return topic
    }

    @Test func seedPromptIncludesReaderIntentContext() {
        let prompt = SemanticSeedPlanner.userPrompt(
            topic: topicWithIntent(),
            masks: ["как", "какой"]
        )

        #expect(prompt.contains("Задача читателя:"))
        #expect(prompt.contains("обеспечить безопасность и освободить руки"))
        #expect(prompt.contains("страх навредить развитию"))
        #expect(prompt.contains("чек-лист критериев выбора"))
    }

    @Test func seedPromptKeepsExplicitMissingIntentFallback() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let prompt = SemanticSeedPlanner.userPrompt(topic: topic, masks: ["как"])

        #expect(prompt.contains("Карта задачи читателя не заполнена."))
    }

    @Test func relevancePromptIncludesReaderIntentAndLongTailRule() {
        let prompt = SemanticAgentAnalyzer.userPrompt(
            topic: topicWithIntent(),
            queries: [WordstatPhrase(text: "какой манеж выбрать", frequency: 120)]
        )

        #expect(prompt.contains("Задача читателя:"))
        #expect(prompt.contains("родитель ребёнка шести месяцев"))
        #expect(prompt.contains("какой манеж выбрать — 120"))
        #expect(prompt.contains("10 длинных запросов из 3-7 слов"))
    }

    @Test func relevancePromptKeepsExplicitMissingIntentFallback() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let prompt = SemanticAgentAnalyzer.userPrompt(
            topic: topic,
            queries: [WordstatPhrase(text: "лечение рака простаты", frequency: 300)]
        )

        #expect(prompt.contains("Карта задачи читателя не заполнена."))
    }

    @Test func relevanceSystemPromptKeepsAcademicAndWrongIntentRules() {
        #expect(SemanticAgentAnalyzer.systemPrompt.contains("академические"))
        #expect(SemanticAgentAnalyzer.systemPrompt.contains("интент"))
        #expect(SemanticAgentAnalyzer.systemPrompt.contains("типом статьи"))
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
cd SEOContentCreator
xcodebuild test \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationTask2 \
  -only-testing:SEOContentCreatorTests/SemanticReaderIntentPromptTests
```

Expected: compilation fails because `SemanticAgentAnalyzer.userPrompt` and
`systemPrompt` are private; after exposing them, assertions still fail because
neither semantic user prompt contains the reader-intent block.

- [ ] **Step 3: Add reader intent to the seed-planning prompt**

In `SemanticSeedPlanner.userPrompt`, add:

```swift
let readerIntent = ReaderIntentPromptRenderer.render(topic: topic)
```

Return:

```swift
"""
Тема: \(topic.title)
Тип статьи: \(topic.articleType.title)

\(readerIntent)

Используй задачу читателя как рамку для выбора релевантных вариантов темы,
сокращений, написаний, масок и уточнений. Не выдумывай спрос и частотность.

Разрешённые вопросительные слова:
\(masks.joined(separator: ", "))

Верни JSON:
{"synonyms":["варианты названия темы: сокращения, разговорные и профессиональные термины, латиница и кириллица"],"masks":["вопросительные слова из списка выше, подходящие теме"],"tails":["уточнения: лечение, цена, симптомы, отзывы, гео — подходящие именно этой теме и задаче читателя"]}
"""
```

- [ ] **Step 4: Expose and extend the relevance prompt**

Change the two prompt arguments in `SemanticAgentAnalyzer.analyze` to:

```swift
Self.systemPrompt,
Self.userPrompt(topic: topic, queries: queries)
```

Replace the private instance system prompt with the same text exposed as an
internal static constant:

```swift
static let systemPrompt = """
Ты SEO-аналитик медицинского сайта. Верни только JSON без Markdown.
Решай, какие запросы стоит включить в семантику темы, а какие не стоит.
Отклоняй академические и учебные формулировки, а также запросы,
интент которых не совпадает с типом статьи.
"""
```

Replace the private instance user-prompt method with:

```swift
static func userPrompt(topic: Topic, queries: [WordstatPhrase]) -> String {
    let readerIntent = ReaderIntentPromptRenderer.render(topic: topic)
    return """
    Тема: \(topic.title)
    Тип статьи: \(topic.articleType.title)

    \(readerIntent)

    Оценивай релевантность не только названию темы, но и целевой аудитории,
    практической задаче, критерию успеха и барьерам из карты. Карта — контекст:
    не выдумывай спрос, медицинские факты или обещания и не эксплуатируй страхи.

    Кандидаты (запрос — частотность):
    \(queries.map { "- \($0.text) — \($0.frequency)" }.joined(separator: "\n"))

    Дополнительно составь 10 длинных запросов из 3-7 слов, которые, по твоему
    мнению, интересны целевой аудитории, и верни их в поле longTail.

    Верни JSON:
    {"keywords":[{"query":"...","recommendation":"include|exclude","reasonCategory":"none|junk|offTopic|lowQuality|tooBroad|wrongIntent|other","explanation":"короткая причина"}],"longTail":["..."]}
    """
}
```

The system-prompt wording remains unchanged; only its visibility and static
ownership change so the existing rules have a focused regression test.

- [ ] **Step 5: Run prompt tests**

Run:

```bash
cd SEOContentCreator
xcodebuild test \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationTask2 \
  -only-testing:SEOContentCreatorTests/SemanticReaderIntentPromptTests
```

Expected: five tests pass.

- [ ] **Step 6: Commit Task 2 only**

```bash
git add \
  SEOContentCreator/SEOContentCreator/Logic/SemanticSeedPlanner.swift \
  SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift \
  SEOContentCreator/SEOContentCreatorTests/SemanticReaderIntentPromptTests.swift
git commit -m "feat: guide semantics with reader intent"
```

Before committing, verify `git diff --cached --name-only` contains only these
three files.

---

### Task 3: Synchronize the semantic snapshot only after successful collection

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift`

**Interfaces:**
- Consumes: `ReaderIntent.acceptedSemanticSnapshot(for:) -> [String]`
- Produces: successful `SemanticCollectionRunner.run` updates
  `topic.readerIntent?.semanticSnapshot`
- Preserves: failures before merge leave the previous snapshot unchanged

- [ ] **Step 1: Register ReaderIntent in the runner test container**

In `SemanticCollectionRunnerTests.makeContext`, change the schema list to:

```swift
let container = try ModelContainer(
    for: Topic.self, ReaderIntent.self, SemanticKeyword.self,
    SemanticFunnelEntry.self,
    configurations: config
)
```

- [ ] **Step 2: Write the failing successful-run test**

Add to `SemanticCollectionRunnerTests`:

```swift
@Test func successfulRunRefreshesReaderIntentSemanticSnapshot() async throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    let intent = ReaderIntent(
        query: "рак груди",
        hiddenGoal: "понять варианты лечения",
        semanticSnapshot: []
    )
    topic.readerIntent = intent
    context.insert(topic)

    let runner = makeRunner(
        pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
        analysis: SemanticAgentAnalysis(
            keywords: [includedResult("рак груди лечение")],
            longTail: []
        )
    )

    try await runner.run(topic: topic, pages: [], context: context)

    #expect(intent.semanticSnapshot == ["рак груди лечение"])
    #expect(ReaderIntentStatus.forTopic(topic) == .ready(summary: "понять варианты лечения"))
}
```

- [ ] **Step 3: Write the failing failure-preservation test**

Add:

```swift
@Test func failedRunDoesNotRefreshReaderIntentSemanticSnapshot() async throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    let intent = ReaderIntent(
        query: "рак груди",
        hiddenGoal: "понять варианты лечения",
        semanticSnapshot: ["старый запрос"]
    )
    topic.readerIntent = intent
    context.insert(topic)

    let runner = makeRunner(
        pulled: [],
        analysis: SemanticAgentAnalysis(keywords: [], longTail: [])
    )

    await #expect(throws: SemanticCollectionRunner.RunError.self) {
        try await runner.run(topic: topic, pages: [], context: context)
    }

    #expect(intent.semanticSnapshot == ["старый запрос"])
}
```

- [ ] **Step 4: Run the two tests and verify RED**

Run:

```bash
cd SEOContentCreator
xcodebuild test \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationTask3 \
  -only-testing:SEOContentCreatorTests/SemanticCollectionRunnerTests/successfulRunRefreshesReaderIntentSemanticSnapshot \
  -only-testing:SEOContentCreatorTests/SemanticCollectionRunnerTests/failedRunDoesNotRefreshReaderIntentSemanticSnapshot
```

Expected: the successful-run test fails because `semanticSnapshot` is still
empty. The failure-preservation test passes, proving the error path baseline.

- [ ] **Step 5: Refresh the snapshot after merge**

In `SemanticCollectionRunner.run`, immediately after:

```swift
SemanticKeywordMerger.merge(survivors, into: topic, decision: .accepted)
```

add:

```swift
if let intent = topic.readerIntent {
    intent.semanticSnapshot = ReaderIntent.acceptedSemanticSnapshot(for: topic)
    intent.updatedAt = .now
}
try context.save()
```

Remove the existing:

```swift
try? context.save()
```

This placement is after seed planning, Wordstat pull, deterministic rules,
relevance analysis, cannibalization checking, and merge. Every earlier thrown
error exits before the snapshot assignment.

- [ ] **Step 6: Run the focused runner tests**

Run:

```bash
cd SEOContentCreator
xcodebuild test \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationTask3 \
  -only-testing:SEOContentCreatorTests/SemanticCollectionRunnerTests
```

Expected: all `SemanticCollectionRunnerTests` pass, including the existing error
and funnel tests.

- [ ] **Step 7: Run the existing stale-status tests**

Run:

```bash
cd SEOContentCreator
xcodebuild test \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationTask3 \
  -only-testing:SEOContentCreatorTests/ReaderIntentTests
```

Expected: the existing manual-change stale test remains green.

- [ ] **Step 8: Commit Task 3 only**

```bash
git add \
  SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift \
  SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift
git commit -m "fix: sync intent after semantic collection"
```

Before committing, verify `git diff --cached --name-only` contains only these
two files.

---

### Task 4: Whole-change verification and manual UI checkpoint

**Files:**
- Verify: all files changed by Tasks 1–3
- Do not modify controlled memory or changelog in this task; that belongs to the
  later confirmed `task-finish` workflow.

**Interfaces:**
- Consumes: all deliverables from Tasks 1–3
- Produces: fresh build/test evidence and a manual-check result

- [ ] **Step 1: Build the application and all tests**

Run:

```bash
cd SEOContentCreator
xcodebuild build-for-testing \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationFinal
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 2: Run every directly affected unit-test suite**

Run:

```bash
cd SEOContentCreator
xcodebuild test-without-building \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationFinal \
  -only-testing:SEOContentCreatorTests/PreparationDestinationTests \
  -only-testing:SEOContentCreatorTests/SemanticReaderIntentPromptTests \
  -only-testing:SEOContentCreatorTests/SemanticCollectionRunnerTests \
  -only-testing:SEOContentCreatorTests/ReaderIntentTests
```

Expected: all selected tests pass with zero failures.

- [ ] **Step 3: Attempt the complete unit-test target**

Run:

```bash
cd SEOContentCreator
xcodebuild test-without-building \
  -project SEOContentCreator.xcodeproj \
  -scheme SEOContentCreator \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SEOContentCreatorCoordinationFinal \
  -only-testing:SEOContentCreatorTests
```

Expected: the complete unit target passes. If the known CLI test-runner hang
recurs, stop the hung runner, report it explicitly, and rely only on the
successfully completed focused suites plus `build-for-testing`; do not describe
the full target as passing.

- [ ] **Step 4: Check invariants and diff hygiene**

Read the active semantic and pipeline decisions in `ai/decisions.md`, then run:

```bash
git diff --check
git diff --name-only
git status --short
```

Verify:

- no protected architecture file changed;
- `project.pbxproj`, Xcode UI state, `.claude/worktrees/`, and
  `ai/current-task.md` are not staged by implementation commits;
- no storage schema or dependency changed;
- no unrelated refactoring entered the diff.

- [ ] **Step 5: Perform the manual UI checklist**

Run the app from Xcode or the built Debug product and check:

1. `Задача читателя` is above `Семантика`;
2. clicking Semantics opens the dedicated sheet when the inspector is visible;
3. hide the inspector and click Semantics again; the same sheet opens;
4. without reader intent, the orange warning appears and all semantics controls
   remain enabled;
5. with saved reader intent, the warning is absent;
6. after a successful automatic collection, both preparation rows are ready;
7. after manually changing an accepted/required decision, the reader-intent row
   shows `Семантика изменилась`;
8. the changed states remain readable in light and dark appearance.

If live Wordstat/OpenAI credentials are not available, complete items 1–5 and 8,
and report items 6–7 as not manually verified but covered by unit tests.

- [ ] **Step 6: Perform an evidence-backed code review**

Review the complete diff against:

`docs/superpowers/specs/2026-07-23-reader-intent-semantics-coordination-design.md`

Resolve every Critical and Important finding. Re-run the affected focused tests
after any correction. Use a reviewer subagent only if the user explicitly chose
subagent-driven execution; otherwise perform the same review inline from files,
diffs, and fresh test output.

- [ ] **Step 7: Final verification after review corrections**

Repeat Steps 1, 2, and 4 using fresh command output. Only then report the
implementation state and propose `task-finish`; do not close the task
automatically.
