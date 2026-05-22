# Generation Core (Sub-project 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AI text generation to the app — three ИИ-автор stages (Черновик, Продуктовые блоки, Семантика-в-текст), a single version lane, side-by-side comparison with diff highlighting, and accept/reject of changes.

**Architecture:** Layered services (Variant B). Four AI-layer blocks — `KeychainService`, `PromptBuilder`, `OpenAIClient`, `StageExecutor` — each with one responsibility. Pure logic (prompt building, SSE parsing, diff, output parsing, hybrid assembly) is extracted into testable functions. SwiftData stores `ArticleVersion`, `GenerationJob`, `StageTemplate`. Streaming uses `AsyncThrowingStream`; UI binds to an `@Observable` executor.

**Tech Stack:** SwiftUI, SwiftData, Swift structured concurrency (`async/await`, `AsyncThrowingStream`), `URLSession.bytes`, `Security.framework` (Keychain), Swift Testing (`@Test`/`#expect`), OpenAI Chat Completions API (streaming).

**Spec:** `docs/superpowers/specs/2026-05-22-generation-core-design.md` (technical), `docs/superpowers/specs/2026-05-19-content-system-redesign-design.md` (product v7.4).

---

## Conventions (read once)

- **Repo root:** `/Users/zykovsrg/Documents/vibecode/SEOContentCreator`
- **App source root:** `SEOContentCreator/SEOContentCreator/SEOContentCreator/` (folders `Models/`, `Logic/`, `Views/`)
- **Test root:** `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/`
- **New files are auto-added** to the target (Xcode 16 file-system-synchronized groups). No `project.pbxproj` editing.
- **Build:** `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
- **All tests:** `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests`
- **One test:** append `/StructName/methodName`, e.g. `-only-testing:SEOContentCreatorTests/PromptBuilderTests/buildsDraftPrompt`
- **Model enum convention (existing):** store `xxxRaw: String`, expose a computed bridge property. Follow `Topic.articleType` / `KnowledgeNode.nodeType`.
- **Pure-logic convention (existing):** `enum`/`struct` with `static func`, no stored state (see `NodeSuggestion`, `TopicStatus`).
- **Commit after each task** with the message shown in its last step.

---

## File Structure

**Models (`.../SEOContentCreator/Models/`)**
- Create `PipelineStage.swift` — stage enum (draft/productBlocks/semanticsInText), titles, agent name.
- Create `VersionSource.swift` — version source enum.
- Create `JobStatus.swift` — job status enum.
- Create `ArticleVersion.swift` — `@Model`, one snapshot in the version lane.
- Create `GenerationJob.swift` — `@Model`, one AI run record.
- Create `StageTemplate.swift` — `@Model`, prompt template for a stage.
- Modify `Topic.swift` — add `versions`, `jobs`, `currentVersionID`, `semantics`.

**Logic (`.../SEOContentCreator/Logic/`)**
- Create `PromptBuilder.swift` — fills `{{variables}}`.
- Create `ParagraphDiff.swift` — paragraph-level LCS diff.
- Create `OpenAILineParser.swift` — pure SSE-line → token parser.
- Create `StageOutputParser.swift` — splits article body from trailing JSON metadata.
- Create `VersionActions.swift` — assembles hybrid text for partial accept.
- Create `KeychainService.swift` — Keychain read/write.
- Create `OpenAIClient.swift` — streaming HTTP client.
- Create `StageExecutor.swift` — `@Observable` orchestrator.
- Create `StageTemplateSeeder.swift` — seeds default templates.

**Views (`.../SEOContentCreator/Views/`)**
- Create `SettingsView.swift` — API key + model.
- Create `TopicWorkspaceView.swift` — workspace shell (header + stage bar + side-by-side + drawers).
- Create `StageBarView.swift` — stage chips.
- Create `SideBySideView.swift` — two columns, streaming + diff.
- Create `AcceptRejectBar.swift` — accept all / partial / reject.
- Create `VersionLaneView.swift` — version timeline.
- Create `JobLogView.swift` — run log.
- Create `ProductBlocksSheet.swift` — block selection checkboxes.
- Create `SemanticsEditorSheet.swift` — minimal semantics list editor.
- Modify `ContentPlanView.swift` — open workspace (NavigationStack + destination).
- Modify `SEOContentCreatorApp.swift` — register models + add `Settings` scene.

---

# Phase 1 — Data foundation

### Task 1: Stage / source / status enums

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/PipelineStage.swift`
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/VersionSource.swift`
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/JobStatus.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/PipelineStageTests.swift`

- [ ] **Step 1: Write the failing test**

`PipelineStageTests.swift`:
```swift
import Testing
@testable import SEOContentCreator

struct PipelineStageTests {
    @Test func authorStagesHaveAuthorAgent() {
        #expect(PipelineStage.draft.agentName == "ИИ-автор")
        #expect(PipelineStage.productBlocks.agentName == "ИИ-автор")
        #expect(PipelineStage.semanticsInText.agentName == "ИИ-автор")
    }

    @Test func titlesAreRussian() {
        #expect(PipelineStage.draft.title == "Черновик")
        #expect(PipelineStage.semanticsInText.title == "Семантика-в-текст")
    }

    @Test func allCasesRoundTripViaRawValue() {
        for stage in PipelineStage.allCases {
            #expect(PipelineStage(rawValue: stage.rawValue) == stage)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PipelineStageTests`
Expected: FAIL — "cannot find 'PipelineStage' in scope".

- [ ] **Step 3: Write the enums**

`PipelineStage.swift`:
```swift
import Foundation

enum PipelineStage: String, CaseIterable, Identifiable, Codable {
    case draft
    case productBlocks
    case semanticsInText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft:           return "Черновик"
        case .productBlocks:   return "Продуктовые блоки"
        case .semanticsInText: return "Семантика-в-текст"
        }
    }

    /// All three author stages are run by the ИИ-автор agent (spec §2.14).
    var agentName: String { "ИИ-автор" }
}
```

`VersionSource.swift`:
```swift
import Foundation

enum VersionSource: String, Codable {
    case generated
    case manualEdit
    case acceptedFull
    case acceptedPartial
    case rollback
    case importFromDocs

    var title: String {
        switch self {
        case .generated:       return "Сгенерировано"
        case .manualEdit:      return "Ручная правка"
        case .acceptedFull:    return "Принято целиком"
        case .acceptedPartial: return "Принято частично"
        case .rollback:        return "Откат"
        case .importFromDocs:  return "Импорт из Docs"
        }
    }
}
```

`JobStatus.swift`:
```swift
import Foundation

enum JobStatus: String, Codable {
    case running
    case success
    case error
    case cancelled

    var title: String {
        switch self {
        case .running:   return "Выполняется"
        case .success:   return "Успех"
        case .error:     return "Ошибка"
        case .cancelled: return "Отменён"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PipelineStageTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/PipelineStage.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/VersionSource.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/JobStatus.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/PipelineStageTests.swift
git commit -m "feat: add pipeline stage, version source, job status enums"
```

---

### Task 2: ArticleVersion model

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/ArticleVersion.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/ArticleVersionTests.swift`

- [ ] **Step 1: Write the failing test**

`ArticleVersionTests.swift`:
```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct ArticleVersionTests {
    @Test func generatedVersionExposesStageAndSource() {
        let v = ArticleVersion(stage: .draft, source: .generated, text: "Текст", agentName: "ИИ-автор")
        #expect(v.stageRaw == "draft")
        #expect(v.source == .generated)
        #expect(v.stageTitle == "Черновик")
        #expect(v.isArchived == false)
        #expect(v.uuid != ArticleVersion(stage: .draft, source: .generated, text: "x").uuid)
    }

    @Test func manualEditVersionHasReadableTitle() {
        let v = ArticleVersion(stageLabel: "manualEdit", source: .manualEdit, text: "Текст")
        #expect(v.stageTitle == "Ручная правка")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ArticleVersionTests`
Expected: FAIL — "cannot find 'ArticleVersion' in scope".

- [ ] **Step 3: Write the model**

`ArticleVersion.swift`:
```swift
import Foundation
import SwiftData

@Model
final class ArticleVersion {
    var uuid: UUID
    var stageRaw: String          // PipelineStage.rawValue, or "manualEdit"/"rollback"/"importFromDocs"
    var sourceRaw: String
    var text: String
    var h1: String?
    var seoTitle: String?
    var seoDescription: String?
    var agentName: String?
    var templateID: UUID?
    var modelName: String?
    var note: String?
    var isArchived: Bool
    var createdAt: Date

    @Relationship var topic: Topic?

    /// Designated init with an arbitrary stage label string (used for manualEdit/rollback).
    init(
        stageLabel: String,
        source: VersionSource,
        text: String,
        agentName: String? = nil,
        templateID: UUID? = nil,
        modelName: String? = nil
    ) {
        self.uuid = UUID()
        self.stageRaw = stageLabel
        self.sourceRaw = source.rawValue
        self.text = text
        self.agentName = agentName
        self.templateID = templateID
        self.modelName = modelName
        self.isArchived = false
        self.createdAt = .now
    }

    /// Convenience init for a known pipeline stage.
    convenience init(
        stage: PipelineStage,
        source: VersionSource,
        text: String,
        agentName: String? = nil,
        templateID: UUID? = nil,
        modelName: String? = nil
    ) {
        self.init(stageLabel: stage.rawValue, source: source, text: text,
                  agentName: agentName, templateID: templateID, modelName: modelName)
    }

    var source: VersionSource {
        get { VersionSource(rawValue: sourceRaw) ?? .generated }
        set { sourceRaw = newValue.rawValue }
    }

    var stageTitle: String {
        if let stage = PipelineStage(rawValue: stageRaw) { return stage.title }
        switch stageRaw {
        case "manualEdit":     return "Ручная правка"
        case "rollback":       return "Откат"
        case "importFromDocs": return "Импорт из Docs"
        default:               return stageRaw
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ArticleVersionTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/ArticleVersion.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/ArticleVersionTests.swift
git commit -m "feat: add ArticleVersion model"
```

---

### Task 3: GenerationJob model

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/GenerationJob.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/GenerationJobTests.swift`

- [ ] **Step 1: Write the failing test**

`GenerationJobTests.swift`:
```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct GenerationJobTests {
    @Test func newJobIsRunning() {
        let job = GenerationJob(stage: .draft, agentName: "ИИ-автор", modelName: "gpt-4.1")
        #expect(job.status == .running)
        #expect(job.stageRaw == "draft")
        #expect(job.finishedAt == nil)
    }

    @Test func canMarkSuccess() {
        let job = GenerationJob(stage: .draft, agentName: "ИИ-автор", modelName: "gpt-4.1")
        job.status = .success
        job.finishedAt = .now
        #expect(job.status == .success)
        #expect(job.finishedAt != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/GenerationJobTests`
Expected: FAIL — "cannot find 'GenerationJob' in scope".

- [ ] **Step 3: Write the model**

`GenerationJob.swift`:
```swift
import Foundation
import SwiftData

@Model
final class GenerationJob {
    var uuid: UUID
    var stageRaw: String
    var agentName: String
    var modelName: String
    var statusRaw: String
    var startedAt: Date
    var finishedAt: Date?
    var errorMessage: String?
    var resultVersionID: UUID?

    @Relationship var topic: Topic?

    init(stage: PipelineStage, agentName: String, modelName: String) {
        self.uuid = UUID()
        self.stageRaw = stage.rawValue
        self.agentName = agentName
        self.modelName = modelName
        self.statusRaw = JobStatus.running.rawValue
        self.startedAt = .now
    }

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }

    var stageTitle: String { PipelineStage(rawValue: stageRaw)?.title ?? stageRaw }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/GenerationJobTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/GenerationJob.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/GenerationJobTests.swift
git commit -m "feat: add GenerationJob model"
```

---

### Task 4: StageTemplate model

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/StageTemplate.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/StageTemplateTests.swift`

- [ ] **Step 1: Write the failing test**

`StageTemplateTests.swift`:
```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct StageTemplateTests {
    @Test func defaultsAreSet() {
        let t = StageTemplate(stage: .draft, systemPrompt: "Ты автор", userPromptTemplate: "Тема: {{тема}}")
        #expect(t.stageRaw == "draft")
        #expect(t.modelName == "gpt-4.1")
        #expect(t.temperature == 0.6)
        #expect(t.maxTokens == 8000)
        #expect(t.articleTypeRaw == nil)   // universal
        #expect(t.templateVersion == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateTests`
Expected: FAIL — "cannot find 'StageTemplate' in scope".

- [ ] **Step 3: Write the model**

`StageTemplate.swift`:
```swift
import Foundation
import SwiftData

@Model
final class StageTemplate {
    var uuid: UUID
    var stageRaw: String
    var articleTypeRaw: String?   // nil = universal (applies to all article types)
    var systemPrompt: String
    var userPromptTemplate: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var templateVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        stage: PipelineStage,
        articleType: ArticleType? = nil,
        systemPrompt: String,
        userPromptTemplate: String,
        modelName: String = "gpt-4.1",
        temperature: Double = 0.6,
        maxTokens: Int = 8000,
        templateVersion: Int = 1
    ) {
        self.uuid = UUID()
        self.stageRaw = stage.rawValue
        self.articleTypeRaw = articleType?.rawValue
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.templateVersion = templateVersion
        self.createdAt = .now
        self.updatedAt = .now
    }

    var stage: PipelineStage? { PipelineStage(rawValue: stageRaw) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/StageTemplate.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/StageTemplateTests.swift
git commit -m "feat: add StageTemplate model"
```

---

### Task 5: Extend Topic + register models in container

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/TopicVersionsTests.swift`

- [ ] **Step 1: Write the failing test**

`TopicVersionsTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

struct TopicVersionsTests {
    @Test func currentVersionResolvesByID() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
            configurations: config
        )
        let context = ModelContext(container)

        let topic = Topic(title: "Тест", articleType: .disease)
        context.insert(topic)
        let v = ArticleVersion(stage: .draft, source: .generated, text: "Черновик")
        v.topic = topic
        context.insert(v)
        topic.currentVersionID = v.uuid

        #expect(topic.currentVersion?.uuid == v.uuid)
        #expect(topic.semantics.isEmpty)
    }

    @Test func currentVersionNilWhenUnset() {
        let topic = Topic(title: "Тест", articleType: .disease)
        #expect(topic.currentVersion == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/TopicVersionsTests`
Expected: FAIL — "value of type 'Topic' has no member 'currentVersionID'".

- [ ] **Step 3: Extend Topic**

In `Topic.swift`, add these stored properties after `var publishedAt: Date?` (line 14):
```swift
    var currentVersionID: UUID?
    var semantics: [String]
```
Add these relationships after the existing `@Relationship var attachedNodes: [KnowledgeNode]` (line 18):
```swift
    @Relationship(deleteRule: .cascade, inverse: \ArticleVersion.topic)
    var versions: [ArticleVersion]
    @Relationship(deleteRule: .cascade, inverse: \GenerationJob.topic)
    var jobs: [GenerationJob]
```
In `init(...)`, after `self.attachedNodes = []` (line 34) add:
```swift
        self.semantics = []
        self.versions = []
        self.jobs = []
```
Add this computed helper after the `articleType` computed property (after line 44):
```swift
    var currentVersion: ArticleVersion? {
        guard let id = currentVersionID else { return nil }
        return versions.first { $0.uuid == id }
    }
```

- [ ] **Step 4: Register the new models in the container**

In `SEOContentCreatorApp.swift`, replace line 10:
```swift
        .modelContainer(for: [Topic.self, KnowledgeNode.self])
```
with:
```swift
        .modelContainer(for: [
            Topic.self, KnowledgeNode.self,
            ArticleVersion.self, GenerationJob.self, StageTemplate.self
        ])
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/TopicVersionsTests`
Expected: PASS (2 tests).

> If a migration error appears at app launch later (existing on-disk store), the local store can be reset during smoke testing — there is no production data yet (see sub-project 2 handoff note). Tests use in-memory stores and are unaffected.

- [ ] **Step 6: Run the full suite to confirm no regressions**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests`
Expected: PASS (all existing + new tests).

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Models/Topic.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/TopicVersionsTests.swift
git commit -m "feat: extend Topic with versions, jobs, semantics; register models"
```

---

# Phase 2 — Pure logic (no I/O)

### Task 6: PromptBuilder

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

`PromptBuilderTests.swift`:
```swift
import Testing
@testable import SEOContentCreator

struct PromptBuilderTests {
    private func draftTemplate() -> StageTemplate {
        StageTemplate(
            stage: .draft,
            systemPrompt: "Ты медицинский автор.",
            userPromptTemplate: "Тема: {{тема}}\nТип: {{тип}}\nОбъём: {{объём}}\nНаправление: {{направление}}\nПреимущества: {{преимущества}}"
        )
    }

    @Test func substitutesBriefVariables() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction, content: "Описание ЛТ")
        let adv = KnowledgeNode(title: "Одно посещение", type: .advantage, content: "Лечение за один визит")
        let topic = Topic(title: "Рак простаты", articleType: .disease, targetVolume: 4000, direction: dir)
        topic.attachedNodes = [adv]

        let result = PromptBuilder().build(template: draftTemplate(), topic: topic, currentText: nil)

        #expect(result.system == "Ты медицинский автор.")
        #expect(result.user.contains("Тема: Рак простаты"))
        #expect(result.user.contains("Тип: Заболевание"))
        #expect(result.user.contains("Объём: 4000"))
        #expect(result.user.contains("Описание ЛТ"))
        #expect(result.user.contains("Лечение за один визит"))
    }

    @Test func unknownPlaceholdersLeftAsIs() {
        let t = StageTemplate(stage: .draft, systemPrompt: "x", userPromptTemplate: "Привет {{неизвестно}}")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(result.user == "Привет {{неизвестно}}")
    }

    @Test func currentTextAndSemanticsSubstituted() {
        let t = StageTemplate(stage: .semanticsInText, systemPrompt: "x",
                              userPromptTemplate: "Текст: {{текущий_текст}}\nЗапросы: {{семантика}}")
        let topic = Topic(title: "T", articleType: .info)
        topic.semantics = ["рак простаты лечение", "лучевая терапия цена"]
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "Готовый текст")
        #expect(result.user.contains("Текст: Готовый текст"))
        #expect(result.user.contains("рак простаты лечение"))
        #expect(result.user.contains("лучевая терапия цена"))
    }

    @Test func selectedBlocksAppendedWhenPresent() {
        let t = StageTemplate(stage: .productBlocks, systemPrompt: "x",
                              userPromptTemplate: "Текст: {{текущий_текст}}")
        let topic = Topic(title: "T", articleType: .service)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "Базовый текст",
                                           selectedBlocks: ["CTA", "Блок врача"])
        #expect(result.user.contains("CTA"))
        #expect(result.user.contains("Блок врача"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptBuilderTests`
Expected: FAIL — "cannot find 'PromptBuilder' in scope".

- [ ] **Step 3: Write the implementation**

`PromptBuilder.swift`:
```swift
import Foundation

struct PromptBuilder {
    func build(
        template: StageTemplate,
        topic: Topic,
        currentText: String?,
        selectedBlocks: [String] = []
    ) -> (system: String, user: String) {
        var user = template.userPromptTemplate

        let advantages = topic.attachedNodes
            .filter { $0.nodeType == .advantage }
            .map { $0.content.isEmpty ? $0.title : $0.content }
            .joined(separator: "\n")

        let sources = (topic.direction?.sources ?? []).joined(separator: "\n")
        let semantics = topic.semantics.joined(separator: "\n")

        let substitutions: [String: String] = [
            "{{тема}}": topic.title,
            "{{тип}}": topic.articleType.title,
            "{{объём}}": topic.targetVolume.map(String.init) ?? "",
            "{{направление}}": topic.direction?.content ?? topic.direction?.title ?? "",
            "{{врач_данные}}": topic.doctor?.content ?? "",
            "{{преимущества}}": advantages,
            "{{источники_направления}}": sources,
            "{{семантика}}": semantics,
            "{{текущий_текст}}": currentText ?? ""
        ]
        for (key, value) in substitutions {
            user = user.replacingOccurrences(of: key, with: value)
        }

        if !selectedBlocks.isEmpty {
            user += "\n\nВключить продуктовые блоки: " + selectedBlocks.joined(separator: ", ")
        }

        return (template.systemPrompt, user)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptBuilderTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift
git commit -m "feat: add PromptBuilder with variable substitution"
```

---

### Task 7: ParagraphDiff

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/ParagraphDiff.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/ParagraphDiffTests.swift`

- [ ] **Step 1: Write the failing test**

`ParagraphDiffTests.swift`:
```swift
import Testing
@testable import SEOContentCreator

struct ParagraphDiffTests {
    @Test func identicalTextsAllUnchanged() {
        let old = "Абзац 1\n\nАбзац 2"
        let new = "Абзац 1\n\nАбзац 2"
        let lines = ParagraphDiff.diff(old: old, new: new)
        #expect(lines.allSatisfy { $0.kind == .unchanged })
        #expect(lines.count == 2)
    }

    @Test func addedParagraphMarked() {
        let old = "Абзац 1"
        let new = "Абзац 1\n\nАбзац 2"
        let lines = ParagraphDiff.diff(old: old, new: new)
        #expect(lines.contains { $0.kind == .added && $0.text == "Абзац 2" })
        #expect(lines.contains { $0.kind == .unchanged && $0.text == "Абзац 1" })
    }

    @Test func removedParagraphMarked() {
        let old = "Абзац 1\n\nАбзац 2"
        let new = "Абзац 1"
        let lines = ParagraphDiff.diff(old: old, new: new)
        #expect(lines.contains { $0.kind == .removed && $0.text == "Абзац 2" })
    }

    @Test func newParagraphsHelperReturnsOnlyNewSide() {
        let old = "A\n\nB"
        let new = "A\n\nC"
        let right = ParagraphDiff.newSide(old: old, new: new)
        #expect(right.contains { $0.kind == .added && $0.text == "C" })
        #expect(right.contains { $0.kind == .unchanged && $0.text == "A" })
        #expect(right.allSatisfy { $0.kind != .removed })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ParagraphDiffTests`
Expected: FAIL — "cannot find 'ParagraphDiff' in scope".

- [ ] **Step 3: Write the implementation**

`ParagraphDiff.swift`:
```swift
import Foundation

enum ParagraphDiffKind {
    case unchanged
    case added
    case removed
}

struct ParagraphDiffLine: Equatable {
    let text: String
    let kind: ParagraphDiffKind
}

enum ParagraphDiff {
    static func paragraphs(_ s: String) -> [String] {
        s.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Merged diff over paragraphs using a Longest Common Subsequence.
    static func diff(old: String, new: String) -> [ParagraphDiffLine] {
        let a = paragraphs(old)
        let b = paragraphs(new)
        let lcs = lcsTable(a, b)
        var result: [ParagraphDiffLine] = []
        var i = a.count, j = b.count
        var reversed: [ParagraphDiffLine] = []
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                reversed.append(ParagraphDiffLine(text: a[i - 1], kind: .unchanged))
                i -= 1; j -= 1
            } else if lcs[i - 1][j] >= lcs[i][j - 1] {
                reversed.append(ParagraphDiffLine(text: a[i - 1], kind: .removed))
                i -= 1
            } else {
                reversed.append(ParagraphDiffLine(text: b[j - 1], kind: .added))
                j -= 1
            }
        }
        while i > 0 { reversed.append(ParagraphDiffLine(text: a[i - 1], kind: .removed)); i -= 1 }
        while j > 0 { reversed.append(ParagraphDiffLine(text: b[j - 1], kind: .added)); j -= 1 }
        result = reversed.reversed()
        return result
    }

    /// Right-column view: only `.unchanged` and `.added` lines (the new version).
    static func newSide(old: String, new: String) -> [ParagraphDiffLine] {
        diff(old: old, new: new).filter { $0.kind != .removed }
    }

    private static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if a.isEmpty || b.isEmpty { return table }
        for x in 1...a.count {
            for y in 1...b.count {
                table[x][y] = a[x - 1] == b[y - 1]
                    ? table[x - 1][y - 1] + 1
                    : max(table[x - 1][y], table[x][y - 1])
            }
        }
        return table
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ParagraphDiffTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/ParagraphDiff.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/ParagraphDiffTests.swift
git commit -m "feat: add paragraph-level LCS diff"
```

---

### Task 8: OpenAILineParser (SSE)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/OpenAILineParser.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/OpenAILineParserTests.swift`

- [ ] **Step 1: Write the failing test**

`OpenAILineParserTests.swift`:
```swift
import Testing
@testable import SEOContentCreator

struct OpenAILineParserTests {
    @Test func parsesContentToken() {
        let line = #"data: {"choices":[{"delta":{"content":"Привет"}}]}"#
        #expect(OpenAILineParser.parse(line: line) == .token("Привет"))
    }

    @Test func recognisesDone() {
        #expect(OpenAILineParser.parse(line: "data: [DONE]") == .done)
    }

    @Test func ignoresEmptyAndNonData() {
        #expect(OpenAILineParser.parse(line: "") == .ignore)
        #expect(OpenAILineParser.parse(line: ": keep-alive") == .ignore)
    }

    @Test func ignoresDeltaWithoutContent() {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        #expect(OpenAILineParser.parse(line: line) == .ignore)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/OpenAILineParserTests`
Expected: FAIL — "cannot find 'OpenAILineParser' in scope".

- [ ] **Step 3: Write the implementation**

`OpenAILineParser.swift`:
```swift
import Foundation

enum OpenAILineResult: Equatable {
    case token(String)
    case done
    case ignore
}

enum OpenAILineParser {
    /// Parses one SSE line from the OpenAI Chat Completions stream.
    static func parse(line: String) -> OpenAILineResult {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return .ignore }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return .ignore }
        return .token(content)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/OpenAILineParserTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/OpenAILineParser.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/OpenAILineParserTests.swift
git commit -m "feat: add OpenAI SSE line parser"
```

---

### Task 9: StageOutputParser (body + metadata)

The semanticsInText stage asks the model to append a JSON block. This parser splits the article body from that trailing JSON and extracts `h1`, `seoTitle`, `seoDescription`, and `embeddedQueries`/`notes`.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/StageOutputParser.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/StageOutputParserTests.swift`

- [ ] **Step 1: Write the failing test**

`StageOutputParserTests.swift`:
```swift
import Testing
@testable import SEOContentCreator

struct StageOutputParserTests {
    @Test func draftStageReturnsBodyOnly() {
        let raw = "H1\n\nТело статьи"
        let out = StageOutputParser.parse(rawText: raw, stage: .draft)
        #expect(out.body == "H1\n\nТело статьи")
        #expect(out.h1 == nil)
        #expect(out.seoTitle == nil)
    }

    @Test func semanticsStageExtractsTrailingJSON() {
        let raw = """
        Тело статьи с ключами.

        ```json
        {"h1":"Рак простаты","seoTitle":"Лечение рака простаты","seoDescription":"Описание","embeddedQueries":["рак простаты"],"notes":"всё ок"}
        ```
        """
        let out = StageOutputParser.parse(rawText: raw, stage: .semanticsInText)
        #expect(out.body == "Тело статьи с ключами.")
        #expect(out.h1 == "Рак простаты")
        #expect(out.seoTitle == "Лечение рака простаты")
        #expect(out.seoDescription == "Описание")
        #expect(out.embeddedQueries == ["рак простаты"])
        #expect(out.notes == "всё ок")
    }

    @Test func semanticsStageWithoutJSONReturnsBody() {
        let raw = "Просто текст без метаданных"
        let out = StageOutputParser.parse(rawText: raw, stage: .semanticsInText)
        #expect(out.body == "Просто текст без метаданных")
        #expect(out.h1 == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageOutputParserTests`
Expected: FAIL — "cannot find 'StageOutputParser' in scope".

- [ ] **Step 3: Write the implementation**

`StageOutputParser.swift`:
```swift
import Foundation

struct StageOutput {
    var body: String
    var h1: String?
    var seoTitle: String?
    var seoDescription: String?
    var embeddedQueries: [String]
    var notes: String?
}

enum StageOutputParser {
    /// For semanticsInText, the model appends a ```json {...}``` block with metadata.
    /// Other stages return plain body text.
    static func parse(rawText: String, stage: PipelineStage) -> StageOutput {
        guard stage == .semanticsInText else {
            return StageOutput(body: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
                               h1: nil, seoTitle: nil, seoDescription: nil,
                               embeddedQueries: [], notes: nil)
        }

        guard let range = rawText.range(of: "```json"),
              let endRange = rawText.range(of: "```", range: range.upperBound..<rawText.endIndex) else {
            return StageOutput(body: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
                               h1: nil, seoTitle: nil, seoDescription: nil,
                               embeddedQueries: [], notes: nil)
        }

        let body = String(rawText[rawText.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = String(rawText[range.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return StageOutput(body: body, h1: nil, seoTitle: nil, seoDescription: nil,
                               embeddedQueries: [], notes: nil)
        }

        return StageOutput(
            body: body,
            h1: json["h1"] as? String,
            seoTitle: json["seoTitle"] as? String,
            seoDescription: json["seoDescription"] as? String,
            embeddedQueries: json["embeddedQueries"] as? [String] ?? [],
            notes: json["notes"] as? String
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageOutputParserTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/StageOutputParser.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/StageOutputParserTests.swift
git commit -m "feat: add stage output parser for body + metadata"
```

---

### Task 10: VersionActions (hybrid assembly for partial accept)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/VersionActions.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/VersionActionsTests.swift`

- [ ] **Step 1: Write the failing test**

`VersionActionsTests.swift`:
```swift
import Testing
@testable import SEOContentCreator

struct VersionActionsTests {
    @Test func acceptsSelectedNewParagraphsKeepsRestFromOld() {
        let old = "A\n\nB\n\nC"
        let new = "A2\n\nB2\n\nC2"
        // accept only paragraphs at index 0 and 2 from new; index 1 stays old
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [0, 2])
        #expect(hybrid == "A2\n\nB\n\nC2")
    }

    @Test func emptySelectionReturnsOld() {
        let old = "A\n\nB"
        let new = "X\n\nY"
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [])
        #expect(hybrid == "A\n\nB")
    }

    @Test func fullSelectionReturnsNew() {
        let old = "A\n\nB"
        let new = "X\n\nY"
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [0, 1])
        #expect(hybrid == "X\n\nY")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/VersionActionsTests`
Expected: FAIL — "cannot find 'VersionActions' in scope".

- [ ] **Step 3: Write the implementation**

`VersionActions.swift`:
```swift
import Foundation

enum VersionActions {
    /// Build a hybrid text: take paragraph i from `new` if i is accepted, else from `old`.
    /// Paragraphs are aligned by index; if `new` has more paragraphs, extra accepted ones are appended.
    static func assembleHybrid(old: String, new: String, acceptedNewIndices: Set<Int>) -> String {
        let oldParas = ParagraphDiff.paragraphs(old)
        let newParas = ParagraphDiff.paragraphs(new)
        let count = max(oldParas.count, newParas.count)
        var result: [String] = []
        for i in 0..<count {
            if acceptedNewIndices.contains(i), i < newParas.count {
                result.append(newParas[i])
            } else if i < oldParas.count {
                result.append(oldParas[i])
            }
        }
        return result.joined(separator: "\n\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/VersionActionsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/VersionActions.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/VersionActionsTests.swift
git commit -m "feat: add hybrid text assembly for partial accept"
```

---

# Phase 3 — Services (I/O)

### Task 11: KeychainService

> Note: these tests touch the login keychain with a dedicated test account and clean up after themselves. They pass when run locally via Xcode/xcodebuild on macOS. If a sandbox blocks keychain access, mark this task's tests as environment-dependent (see executing-plans checkpoint).

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/KeychainService.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/KeychainServiceTests.swift`

- [ ] **Step 1: Write the failing test**

`KeychainServiceTests.swift`:
```swift
import Testing
@testable import SEOContentCreator

struct KeychainServiceTests {
    private let account = "test-\(UUID().uuidString)"

    @Test func saveThenLoadReturnsValue() throws {
        try KeychainService.save(apiKey: "sk-test-123", account: account)
        defer { try? KeychainService.deleteAPIKey(account: account) }
        #expect(try KeychainService.loadAPIKey(account: account) == "sk-test-123")
    }

    @Test func loadMissingThrowsNotFound() {
        #expect(throws: KeychainService.KeychainError.notFound) {
            _ = try KeychainService.loadAPIKey(account: "missing-\(UUID().uuidString)")
        }
    }

    @Test func saveOverwritesExisting() throws {
        try KeychainService.save(apiKey: "first", account: account)
        try KeychainService.save(apiKey: "second", account: account)
        defer { try? KeychainService.deleteAPIKey(account: account) }
        #expect(try KeychainService.loadAPIKey(account: account) == "second")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/KeychainServiceTests`
Expected: FAIL — "cannot find 'KeychainService' in scope".

- [ ] **Step 3: Write the implementation**

`KeychainService.swift`:
```swift
import Foundation
import Security

enum KeychainService {
    enum KeychainError: Error, Equatable {
        case notFound
        case unexpectedStatus(OSStatus)
    }

    static let serviceName = "SEOContentCreator.OpenAI"

    static func save(apiKey: String, account: String = "default") throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)   // overwrite semantics
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func loadAPIKey(account: String = "default") throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        return key
    }

    static func deleteAPIKey(account: String = "default") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func hasAPIKey(account: String = "default") -> Bool {
        (try? loadAPIKey(account: account)) != nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/KeychainServiceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/KeychainService.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/KeychainServiceTests.swift
git commit -m "feat: add KeychainService for OpenAI key storage"
```

---

### Task 12: OpenAIClient (streaming)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/OpenAIClient.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/OpenAIClientTests.swift`

- [ ] **Step 1: Write the failing test**

`OpenAIClientTests.swift`:
```swift
import Testing
import Foundation
@testable import SEOContentCreator

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var stubBody = ""
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.stubBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct OpenAIClientTests {
    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func streamsTokensFromSSE() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubBody = """
        data: {"choices":[{"delta":{"content":"Привет"}}]}

        data: {"choices":[{"delta":{"content":", мир"}}]}

        data: [DONE]

        """
        let client = OpenAIClient(session: mockSession())
        var collected = ""
        for try await token in client.streamCompletion(apiKey: "sk-x", system: "s", user: "u", model: "gpt-4.1") {
            collected += token
        }
        #expect(collected == "Привет, мир")
    }

    @Test func unauthorizedThrows() async {
        MockURLProtocol.statusCode = 401
        MockURLProtocol.stubBody = ""
        let client = OpenAIClient(session: mockSession())
        await #expect(throws: OpenAIClient.OpenAIError.unauthorized) {
            for try await _ in client.streamCompletion(apiKey: "bad", system: "s", user: "u", model: "gpt-4.1") {}
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/OpenAIClientTests`
Expected: FAIL — "cannot find 'OpenAIClient' in scope".

- [ ] **Step 3: Write the implementation**

`OpenAIClient.swift`:
```swift
import Foundation

struct OpenAIClient {
    enum OpenAIError: Error, Equatable {
        case unauthorized
        case rateLimited
        case http(Int)
        case badResponse
    }

    let session: URLSession
    let endpoint: URL

    init(session: URLSession = .shared,
         endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!) {
        self.session = session
        self.endpoint = endpoint
    }

    func streamCompletion(
        apiKey: String,
        system: String,
        user: String,
        model: String,
        temperature: Double = 0.6,
        maxTokens: Int = 8000
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": model,
                        "temperature": temperature,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": system],
                            ["role": "user", "content": user]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        switch http.statusCode {
                        case 200...299: break
                        case 401: throw OpenAIError.unauthorized
                        case 429: throw OpenAIError.rateLimited
                        default: throw OpenAIError.http(http.statusCode)
                        }
                    }

                    for try await line in bytes.lines {
                        switch OpenAILineParser.parse(line: line) {
                        case .token(let t): continuation.yield(t)
                        case .done: continuation.finish(); return
                        case .ignore: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/OpenAIClientTests`
Expected: PASS (2 tests).

> If `bytes.lines` does not split the mock body as expected (URLProtocol delivers one chunk), the `.lines` async sequence still splits on newlines correctly. If the unauthorized test is flaky because the error surfaces before headers, confirm the status check runs before line iteration.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/OpenAIClient.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/OpenAIClientTests.swift
git commit -m "feat: add streaming OpenAIClient"
```

---

### Task 13: StageExecutor

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift`

- [ ] **Step 1: Write the failing test**

`StageExecutorTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct StageExecutorTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func cannedStream(_ chunks: [String]) -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                for c in chunks { continuation.yield(c) }
                continuation.finish()
            }
        }
    }

    @Test func successCreatesCurrentVersionAndSuccessfulJob() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease,
                          direction: KnowledgeNode(title: "ЛТ", type: .direction))
        context.insert(topic)
        let template = StageTemplate(stage: .draft, systemPrompt: "s", userPromptTemplate: "{{тема}}")
        context.insert(template)

        let executor = StageExecutor(
            streamProvider: cannedStream(["Часть 1 ", "Часть 2"]),
            keyProvider: { "sk-test" }
        )
        await executor.execute(stage: .draft, topic: topic, template: template,
                               currentText: nil, in: context)

        #expect(executor.isRunning == false)
        #expect(topic.currentVersion?.text == "Часть 1 Часть 2")
        #expect(topic.currentVersion?.stageRaw == "draft")
        #expect(topic.jobs.first?.status == .success)
        #expect(executor.lastErrorMessage == nil)
    }

    @Test func missingKeyProducesErrorJobNoVersion() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let template = StageTemplate(stage: .draft, systemPrompt: "s", userPromptTemplate: "x")
        context.insert(template)

        let executor = StageExecutor(
            streamProvider: cannedStream(["ignored"]),
            keyProvider: { throw KeychainService.KeychainError.notFound }
        )
        await executor.execute(stage: .draft, topic: topic, template: template,
                               currentText: nil, in: context)

        #expect(topic.currentVersion == nil)
        #expect(topic.jobs.first?.status == .error)
        #expect(executor.lastErrorMessage == "Укажите API-ключ в Настройках")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageExecutorTests`
Expected: FAIL — "cannot find 'StageExecutor' in scope".

- [ ] **Step 3: Write the implementation**

`StageExecutor.swift`:
```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class StageExecutor {
    typealias StreamProvider = (
        _ apiKey: String, _ system: String, _ user: String,
        _ model: String, _ temperature: Double, _ maxTokens: Int
    ) -> AsyncThrowingStream<String, Error>
    typealias KeyProvider = () throws -> String

    var streamingText: String = ""
    var isRunning: Bool = false
    var lastErrorMessage: String?

    private let streamProvider: StreamProvider
    private let keyProvider: KeyProvider

    init(streamProvider: @escaping StreamProvider, keyProvider: @escaping KeyProvider) {
        self.streamProvider = streamProvider
        self.keyProvider = keyProvider
    }

    /// Production convenience: wire to KeychainService + OpenAIClient.
    static func live(model: String) -> StageExecutor {
        StageExecutor(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey, system: system, user: user,
                    model: model, temperature: temperature, maxTokens: maxTokens
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() }
        )
    }

    func execute(
        stage: PipelineStage,
        topic: Topic,
        template: StageTemplate,
        currentText: String?,
        selectedBlocks: [String] = [],
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil

        let job = GenerationJob(stage: stage, agentName: stage.agentName, modelName: template.modelName)
        job.topic = topic
        context.insert(job)

        do {
            let key = try keyProvider()
            let prompt = PromptBuilder().build(
                template: template, topic: topic,
                currentText: currentText, selectedBlocks: selectedBlocks
            )
            var collected = ""
            for try await chunk in streamProvider(
                key, prompt.system, prompt.user,
                template.modelName, template.temperature, template.maxTokens
            ) {
                collected += chunk
                streamingText = collected
            }

            let parsed = StageOutputParser.parse(rawText: collected, stage: stage)
            let version = ArticleVersion(
                stage: stage, source: .generated, text: parsed.body,
                agentName: stage.agentName, templateID: template.uuid, modelName: template.modelName
            )
            version.h1 = parsed.h1
            version.seoTitle = parsed.seoTitle
            version.seoDescription = parsed.seoDescription
            version.topic = topic
            context.insert(version)

            topic.currentVersionID = version.uuid
            topic.updatedAt = .now

            job.status = .success
            job.finishedAt = .now
            job.resultVersionID = version.uuid
        } catch {
            job.status = .error
            job.finishedAt = .now
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            job.errorMessage = message
            lastErrorMessage = message
        }

        isRunning = false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageExecutorTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift
git commit -m "feat: add StageExecutor orchestrator"
```

---

### Task 14: StageTemplateSeeder

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift`
- Test: `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/StageTemplateSeederTests.swift`

- [ ] **Step 1: Write the failing test**

`StageTemplateSeederTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct StageTemplateSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func seedsOneTemplatePerStage() throws {
        let context = try makeContext()
        StageTemplateSeeder.seedIfNeeded(in: context)
        let all = try context.fetch(FetchDescriptor<StageTemplate>())
        #expect(all.count == PipelineStage.allCases.count)
        for stage in PipelineStage.allCases {
            #expect(all.contains { $0.stageRaw == stage.rawValue })
        }
    }

    @Test func seedingIsIdempotent() throws {
        let context = try makeContext()
        StageTemplateSeeder.seedIfNeeded(in: context)
        StageTemplateSeeder.seedIfNeeded(in: context)
        let all = try context.fetch(FetchDescriptor<StageTemplate>())
        #expect(all.count == PipelineStage.allCases.count)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateSeederTests`
Expected: FAIL — "cannot find 'StageTemplateSeeder' in scope".

- [ ] **Step 3: Write the implementation**

`StageTemplateSeeder.swift`:
```swift
import Foundation
import SwiftData

enum StageTemplateSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
        let seededStages = Set(existing.map { $0.stageRaw })

        for stage in PipelineStage.allCases where !seededStages.contains(stage.rawValue) {
            let template = makeTemplate(for: stage)
            context.insert(template)
        }
    }

    private static func makeTemplate(for stage: PipelineStage) -> StageTemplate {
        switch stage {
        case .draft:
            return StageTemplate(
                stage: .draft,
                systemPrompt: """
                Ты — медицинский редактор-копирайтер. Пиши достоверно, без искажения фактов, \
                с доказательной осторожностью. Соблюдай читабельность. Не выдумывай имена врачей, \
                процедуры и цифры — используй только переданные данные. Отвечай на русском в формате Markdown.
                """,
                userPromptTemplate: """
                Напиши черновик SEO-статьи.

                Тема: {{тема}}
                Тип статьи: {{тип}}
                Целевой объём (знаков): {{объём}}
                Направление: {{направление}}
                Данные врача: {{врач_данные}}
                Преимущества клиники: {{преимущества}}
                Приоритетные источники: {{источники_направления}}

                Сделай структуру H1/H2/H3 и связный текст. Не добавляй рекламных преувеличений.
                """
            )
        case .productBlocks:
            return StageTemplate(
                stage: .productBlocks,
                systemPrompt: """
                Ты — медицинский редактор. Встраиваешь продуктовые блоки клиники в существующий текст, \
                сохраняя структуру и стиль. Данные берёшь только из переданных. Русский, Markdown.
                """,
                userPromptTemplate: """
                Встрой выбранные продуктовые блоки в текст, не ломая его структуру.

                Текущий текст:
                {{текущий_текст}}

                Преимущества клиники: {{преимущества}}
                Данные врача: {{врач_данные}}

                Верни полный обновлённый текст статьи.
                """
            )
        case .semanticsInText:
            return StageTemplate(
                stage: .semanticsInText,
                systemPrompt: """
                Ты — SEO-редактор. Естественно встраиваешь ключевые запросы в текст без порчи русского языка \
                и без переспама. Не меняешь факты. Русский, Markdown.
                """,
                userPromptTemplate: """
                Встрой ключевые запросы в текст естественно. Учитывай частотность и обязательность. \
                Допиши/поправь H1, сгенерируй Title и Description.

                Текущий текст:
                {{текущий_текст}}

                Ключевые запросы:
                {{семантика}}

                После основного текста статьи добавь блок метаданных строго в таком формате:
                ```json
                {"h1":"...","seoTitle":"...","seoDescription":"...","embeddedQueries":["..."],"notes":"..."}
                ```
                """
            )
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateSeederTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/StageTemplateSeederTests.swift
git commit -m "feat: add starter stage template seeder"
```

---

# Phase 4 — UI (manual smoke tests)

> UI views are verified by building and running the app (Cmd+R) and exercising the flow. No XCUITest. After each task: build succeeds + the described smoke check passes. The shared executor uses `StageExecutor.live(model:)`.

### Task 15: SettingsView + Settings scene

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/SettingsView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`

- [ ] **Step 1: Write `SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @State private var apiKey = ""
    @State private var savedMessage: String?
    @State private var hasKey = KeychainService.hasAPIKey()

    private let models = ["gpt-4.1", "gpt-4o", "gpt-4o-mini"]

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API-ключ", text: $apiKey)
                Picker("Модель", selection: $model) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button("Сохранить ключ") { saveKey() }
                        .disabled(apiKey.isEmpty)
                    if hasKey {
                        Button("Удалить ключ", role: .destructive) { deleteKey() }
                    }
                    Spacer()
                    if hasKey { Label("Ключ сохранён", systemImage: "checkmark.seal").foregroundStyle(.green) }
                }
                if let savedMessage { Text(savedMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 240)
        .navigationTitle("Настройки")
    }

    private func saveKey() {
        do {
            try KeychainService.save(apiKey: apiKey)
            apiKey = ""
            hasKey = true
            savedMessage = "Ключ сохранён в Keychain."
        } catch {
            savedMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func deleteKey() {
        try? KeychainService.deleteAPIKey()
        hasKey = false
        savedMessage = "Ключ удалён."
    }
}
```

- [ ] **Step 2: Add the Settings scene**

In `SEOContentCreatorApp.swift`, after the `WindowGroup { ... }.modelContainer(...)` block (inside `body`, after the closing of WindowGroup's modifier), add:
```swift
        Settings {
            SettingsView()
        }
```
The `body` now contains both `WindowGroup { ... }` and `Settings { ... }`.

- [ ] **Step 3: Build**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Smoke test**

Run the app (Cmd+R in Xcode). Open Settings (⌘,). Enter a fake key, click «Сохранить ключ» → see «Ключ сохранён». Reopen Settings → «Ключ сохранён» badge persists. Click «Удалить ключ» → badge gone.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/SettingsView.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift
git commit -m "feat: add Settings screen for OpenAI key and model"
```

---

### Task 16: TopicWorkspaceView shell + StageBarView + open from Content Plan

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/StageBarView.swift`
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift`

- [ ] **Step 1: Write `StageBarView.swift`**

```swift
import SwiftUI

struct StageBarView: View {
    @Binding var selectedStage: PipelineStage
    var topic: Topic

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PipelineStage.allCases) { stage in
                Button {
                    selectedStage = stage
                } label: {
                    Text(stage.title)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(selectedStage == stage ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
```

- [ ] **Step 2: Write `TopicWorkspaceView.swift` (shell)**

```swift
import SwiftUI
import SwiftData

struct TopicWorkspaceView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @State private var selectedStage: PipelineStage = .draft
    @State private var executor: StageExecutor?
    @State private var comparisonText: String?     // left column (previous current)
    @State private var showVersions = false
    @State private var showLog = false
    @State private var showProductBlocks = false
    @State private var showSemantics = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            StageBarView(selectedStage: $selectedStage, topic: topic)
                .padding(.vertical, 8)
            Divider()
            SideBySideView(
                leftText: comparisonText ?? topic.currentVersion?.text,
                rightText: rightText,
                isStreaming: executor?.isRunning ?? false
            )
            Divider()
            AcceptRejectBar(
                canAct: pendingGeneratedVersion != nil,
                onAcceptAll: acceptAll,
                onAcceptPartial: { /* handled in Task 18 */ },
                onReject: reject
            )
        }
        .navigationTitle(topic.title)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showVersions) { VersionLaneView(topic: topic) { comparisonText = $0.text } }
        .sheet(isPresented: $showLog) { JobLogView(topic: topic) }
        .sheet(isPresented: $showProductBlocks) {
            ProductBlocksSheet(topic: topic) { runStage(.productBlocks, blocks: $0) }
        }
        .sheet(isPresented: $showSemantics) { SemanticsEditorSheet(topic: topic) }
        .onAppear { if executor == nil { executor = .live(model: model) } }
    }

    private var rightText: String? {
        if let executor, executor.isRunning { return executor.streamingText }
        return pendingGeneratedVersion?.text
    }

    /// The most recent generated version that hasn't been archived (awaiting accept/reject).
    private var pendingGeneratedVersion: ArticleVersion? {
        topic.currentVersion?.source == .generated ? topic.currentVersion : nil
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(topic.title).font(.headline)
                Text("\(topic.articleType.title) · \(topic.direction?.title ?? "—")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: runSelectedStage) {
                Label("Запустить этап", systemImage: "play.fill")
            }
            .disabled(executor?.isRunning ?? false)
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem { Button { showSemantics = true } label: { Label("Семантика", systemImage: "list.bullet") } }
        ToolbarItem { Button { showVersions = true } label: { Label("Версии", systemImage: "clock.arrow.circlepath") } }
        ToolbarItem { Button { showLog = true } label: { Label("Лог", systemImage: "doc.text") } }
    }

    private func runSelectedStage() {
        if selectedStage == .productBlocks { showProductBlocks = true; return }
        runStage(selectedStage, blocks: [])
    }

    private func runStage(_ stage: PipelineStage, blocks: [String]) {
        guard let executor else { return }
        comparisonText = topic.currentVersion?.text   // remember pre-generation text for the left column
        let template = fetchTemplate(for: stage)
        let current = topic.currentVersion?.text
        Task {
            await executor.execute(stage: stage, topic: topic, template: template,
                                   currentText: current, selectedBlocks: blocks, in: context)
        }
    }

    private func fetchTemplate(for stage: PipelineStage) -> StageTemplate {
        let raw = stage.rawValue
        let descriptor = FetchDescriptor<StageTemplate>(
            predicate: #Predicate { $0.stageRaw == raw }
        )
        if let found = (try? context.fetch(descriptor))?.first { return found }
        // Fallback: seed then refetch.
        StageTemplateSeeder.seedIfNeeded(in: context)
        return (try? context.fetch(descriptor))?.first
            ?? StageTemplate(stage: stage, systemPrompt: "", userPromptTemplate: "{{текущий_текст}}")
    }

    private func acceptAll() {
        // Generated version is already current; just clear the comparison view.
        comparisonText = nil
    }

    private func reject() {
        guard let pending = pendingGeneratedVersion else { return }
        pending.isArchived = true
        // Restore previous current version: the newest non-archived version before this one.
        let prior = topic.versions
            .filter { !$0.isArchived && $0.uuid != pending.uuid }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        topic.currentVersionID = prior?.uuid
        comparisonText = nil
    }
}
```

- [ ] **Step 3: Wire opening from ContentPlanView**

Replace the body of `ContentPlanView.swift` so the Table is wrapped in a `NavigationStack` and an "Открыть" action navigates to the workspace. Replace lines 15-43 (`var body: some View { ... }`) with:
```swift
    var body: some View {
        NavigationStack {
            Table(visibleTopics, selection: $selection) {
                TableColumn("Тема") { Text($0.title) }
                TableColumn("Тип") { Text($0.articleType.title) }
                TableColumn("Направление") { Text($0.direction?.title ?? "—") }
                TableColumn("Статус") { Text(TopicStatus.compute(for: $0).label) }
            }
            .contextMenu(forSelectionType: Topic.ID.self) { ids in
                if let id = ids.first, let t = topics.first(where: { $0.id == id }) {
                    Button("Открыть") { opened = t }
                    Button("Редактировать") { editingTopic = t }
                    Button("Удалить", role: .destructive) { context.delete(t) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let t = topics.first(where: { $0.id == id }) { opened = t }
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
            .navigationDestination(item: $opened) { TopicWorkspaceView(topic: $0) }
            .sheet(isPresented: $showingBrief) { BriefView(topic: nil) }
            .sheet(item: $editingTopic) { BriefView(topic: $0) }
        }
    }
```
Add this `@State` near the other state properties (after line 11 `@State private var editingTopic: Topic?`):
```swift
    @State private var opened: Topic?
```
> `primaryAction:` on `contextMenu(forSelectionType:)` fires on double-click — that satisfies the frontend-design "double-click opens workspace" requirement.

- [ ] **Step 4: Build**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.
> SideBySideView, AcceptRejectBar, VersionLaneView, JobLogView, ProductBlocksSheet, SemanticsEditorSheet are created in Tasks 17-21. If building Task 16 alone fails because they don't exist yet, implement Tasks 17-21 first, then build. Recommended: write Tasks 16-21 views, then build once at Task 21. Adjust commits accordingly (commit each view file; do the build/smoke at Task 21).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/StageBarView.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift
git commit -m "feat: add topic workspace shell, stage bar, open-on-double-click"
```

---

### Task 17: SideBySideView (streaming + diff)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/SideBySideView.swift`

- [ ] **Step 1: Write `SideBySideView.swift`**

```swift
import SwiftUI

struct SideBySideView: View {
    var leftText: String?
    var rightText: String?
    var isStreaming: Bool

    var body: some View {
        HStack(spacing: 0) {
            column(title: "Текущая версия", content: leftColumn)
            Divider()
            column(title: isStreaming ? "Генерация…" : "Новая версия", content: rightColumn)
        }
    }

    @ViewBuilder private var leftColumn: some View {
        if let leftText, !leftText.isEmpty {
            ScrollView { Text(leftText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
        } else {
            ContentUnavailableView("Нет текущей версии", systemImage: "doc")
        }
    }

    @ViewBuilder private var rightColumn: some View {
        if isStreaming {
            ScrollView { Text(rightText ?? "").frame(maxWidth: .infinity, alignment: .leading).padding() }
        } else if let rightText, let leftText {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(ParagraphDiff.newSide(old: leftText, new: rightText).enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(line.kind == .added ? Color.green.opacity(0.18) : Color.clear)
                    }
                }.padding()
            }
        } else if let rightText {
            ScrollView { Text(rightText).frame(maxWidth: .infinity, alignment: .leading).padding() }
        } else {
            ContentUnavailableView("Запустите этап", systemImage: "play.circle")
        }
    }

    private func column<C: View>(title: String, content: C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary).padding(6)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Build** (with Task 16 in place)

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (once Tasks 18-21 views also exist; otherwise build at Task 21).

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/SideBySideView.swift
git commit -m "feat: add side-by-side view with streaming and paragraph diff"
```

---

### Task 18: AcceptRejectBar + partial-accept sheet

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/AcceptRejectBar.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`

- [ ] **Step 1: Write `AcceptRejectBar.swift`**

```swift
import SwiftUI

struct AcceptRejectBar: View {
    var canAct: Bool
    var onAcceptAll: () -> Void
    var onAcceptPartial: () -> Void
    var onReject: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Отклонить", role: .destructive, action: onReject).disabled(!canAct)
            Button("Принять частично", action: onAcceptPartial).disabled(!canAct)
            Button("Принять всё", action: onAcceptAll).keyboardShortcut(.defaultAction).disabled(!canAct)
        }
        .padding(8)
    }
}
```

- [ ] **Step 2: Wire partial accept in `TopicWorkspaceView.swift`**

Add this state near the other `@State` declarations:
```swift
    @State private var showPartialAccept = false
```
Replace the `onAcceptPartial:` argument in the `AcceptRejectBar(...)` call:
```swift
                onAcceptPartial: { showPartialAccept = true },
```
Add this sheet modifier after the existing `.sheet(isPresented: $showSemantics) { ... }` line:
```swift
        .sheet(isPresented: $showPartialAccept) {
            if let pending = pendingGeneratedVersion, let base = comparisonText {
                PartialAcceptSheet(oldText: base, newText: pending.text) { acceptedIndices in
                    applyPartial(base: base, generated: pending, indices: acceptedIndices)
                }
            }
        }
```
Add these methods inside `TopicWorkspaceView`:
```swift
    private func applyPartial(base: String, generated: ArticleVersion, indices: Set<Int>) {
        let hybrid = VersionActions.assembleHybrid(old: base, new: generated.text, acceptedNewIndices: indices)
        generated.isArchived = true
        let version = ArticleVersion(stage: PipelineStage(rawValue: generated.stageRaw) ?? .draft,
                                     source: .acceptedPartial, text: hybrid)
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
        comparisonText = nil
    }
```

- [ ] **Step 3: Write `PartialAcceptSheet` (in `AcceptRejectBar.swift`, same file)**

Append to `AcceptRejectBar.swift`:
```swift
struct PartialAcceptSheet: View {
    @Environment(\.dismiss) private var dismiss
    var oldText: String
    var newText: String
    var onApply: (Set<Int>) -> Void

    @State private var accepted: Set<Int> = []

    private var newParagraphs: [String] { ParagraphDiff.paragraphs(newText) }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Выберите абзацы из новой версии").font(.headline).padding(.bottom, 4)
            List {
                ForEach(Array(newParagraphs.enumerated()), id: \.offset) { index, para in
                    Toggle(isOn: Binding(
                        get: { accepted.contains(index) },
                        set: { if $0 { accepted.insert(index) } else { accepted.remove(index) } }
                    )) {
                        Text(para).lineLimit(3)
                    }
                }
            }
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Применить") { onApply(accepted); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560, height: 480)
    }
}
```

- [ ] **Step 4: Build** (defer to Task 21 if dependent views missing)

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/AcceptRejectBar.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift
git commit -m "feat: add accept/reject bar and partial-accept sheet"
```

---

### Task 19: VersionLaneView

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/VersionLaneView.swift`

- [ ] **Step 1: Write `VersionLaneView.swift`**

```swift
import SwiftUI
import SwiftData

struct VersionLaneView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic
    var onCompare: (ArticleVersion) -> Void

    @State private var groupByStage = false

    private var versions: [ArticleVersion] {
        topic.versions.filter { !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Вид", selection: $groupByStage) {
                Text("По времени").tag(false)
                Text("По этапам").tag(true)
            }.pickerStyle(.segmented)

            List {
                if groupByStage {
                    ForEach(stageGroups, id: \.0) { stage, items in
                        Section(stage) { ForEach(items) { row($0) } }
                    }
                } else {
                    ForEach(versions) { row($0) }
                }
            }

            HStack { Spacer(); Button("Закрыть") { dismiss() } }
        }
        .padding()
        .frame(width: 520, height: 520)
    }

    private var stageGroups: [(String, [ArticleVersion])] {
        Dictionary(grouping: versions, by: { $0.stageTitle })
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private func row(_ v: ArticleVersion) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(v.stageTitle).font(.subheadline)
                Text("\(v.source.title) · \(v.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if topic.currentVersionID == v.uuid {
                Label("Текущая", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.iconOnly)
            }
            Button("Сравнить") { onCompare(v); dismiss() }
            Button("Сделать текущей") { makeCurrent(v) }
        }
    }

    private func makeCurrent(_ v: ArticleVersion) {
        let rollback = ArticleVersion(stageLabel: "rollback", source: .rollback, text: v.text)
        rollback.topic = topic
        // insert via the topic relationship; context comes from the bound topic
        topic.versions.append(rollback)
        topic.currentVersionID = rollback.uuid
        topic.updatedAt = .now
    }
}
```

- [ ] **Step 2: Build** (defer to Task 21 if needed)

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/VersionLaneView.swift
git commit -m "feat: add version lane view with rollback"
```

---

### Task 20: JobLogView

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/JobLogView.swift`

- [ ] **Step 1: Write `JobLogView.swift`**

```swift
import SwiftUI
import SwiftData

struct JobLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    private var jobs: [GenerationJob] {
        topic.jobs.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Лог темы").font(.headline)
            List(jobs) { job in
                HStack {
                    icon(for: job.status)
                    VStack(alignment: .leading) {
                        Text(job.stageTitle).font(.subheadline)
                        Text("\(job.agentName) · \(job.modelName) · \(job.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = job.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Spacer()
                }
            }
            HStack { Spacer(); Button("Закрыть") { dismiss() } }
        }
        .padding()
        .frame(width: 520, height: 440)
    }

    @ViewBuilder private func icon(for status: JobStatus) -> some View {
        switch status {
        case .running:   Image(systemName: "hourglass").foregroundStyle(.orange)
        case .success:   Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:     Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Build** (defer to Task 21 if needed)

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/JobLogView.swift
git commit -m "feat: add job log view"
```

---

### Task 21: ProductBlocksSheet + SemanticsEditorSheet + full build & smoke

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/ProductBlocksSheet.swift`
- Create: `SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift`

- [ ] **Step 1: Write `ProductBlocksSheet.swift`**

```swift
import SwiftUI
import SwiftData

struct ProductBlocksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic
    var onGenerate: ([String]) -> Void

    // Starter set of product block names; refined in a later sub-project (Шаблоны).
    private let availableBlocks = ["CTA «Записаться»", "Почему мы", "Блок врача", "Преимущества клиники"]
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Выберите продуктовые блоки").font(.headline)
            List {
                ForEach(availableBlocks, id: \.self) { block in
                    Toggle(isOn: Binding(
                        get: { selected.contains(block) },
                        set: { if $0 { selected.insert(block) } else { selected.remove(block) } }
                    )) { Text(block) }
                }
            }
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сгенерировать") { onGenerate(Array(selected)); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 360)
    }
}
```

- [ ] **Step 2: Write `SemanticsEditorSheet.swift`**

```swift
import SwiftUI
import SwiftData

struct SemanticsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @State private var bulkText = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Семантика (по одному запросу в строке)").font(.headline)
            TextEditor(text: $bulkText)
                .font(.body).frame(minHeight: 240).border(.gray.opacity(0.3))
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460, height: 380)
        .onAppear { bulkText = topic.semantics.joined(separator: "\n") }
    }

    private func save() {
        topic.semantics = bulkText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        topic.updatedAt = .now
        dismiss()
    }
}
```

- [ ] **Step 3: Seed templates on launch**

In `SEOContentCreatorApp.swift`, ensure templates exist when the app starts. Add a `.task` to `RootView` instead (it has access to the context). In `RootView.swift`, add to the `NavigationSplitView { ... }` a modifier:
```swift
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
        }
```
And add at the top of `RootView`'s properties:
```swift
    @Environment(\.modelContext) private var context
```
(Add `import SwiftData` to `RootView.swift` if not present.)

- [ ] **Step 4: Full build**

Run: `cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Full test suite**

Run: `cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests`
Expected: PASS (all tests across all tasks).

- [ ] **Step 6: End-to-end smoke test (real API)**

1. Run the app (Cmd+R). If a SwiftData migration error appears, delete the local store (e.g. remove the app's Application Support container) and relaunch — there is no production data.
2. Settings (⌘,) → enter a real OpenAI key → Сохранить.
3. Knowledge Base → ensure at least one `direction` node exists.
4. Content Plan → New topic with title + type + direction → save.
5. Double-click the topic → workspace opens.
6. Click «Запустить этап» (Черновик) → text streams into the right column.
7. After completion, click «Принять всё».
8. Toolbar → «Семантика» → add a few queries → save.
9. Stage bar → «Семантика-в-текст» → run → metadata (H1/Title/Description) appears; diff highlights changes.
10. «Версии» → see the lane; «Лог» → see successful runs.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/ProductBlocksSheet.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreator/Views/RootView.swift
git commit -m "feat: add product blocks and semantics sheets; seed templates on launch"
```

---

### Task 22: Update task memory

**Files:**
- Modify: `ai/current-task.md`
- Modify: `ai/changelog.md`

- [ ] **Step 1:** Update `ai/changelog.md` with a sub-project 3 entry (date 2026-05-22): new models (ArticleVersion, GenerationJob, StageTemplate), AI service layer (KeychainService, PromptBuilder, OpenAIClient, StageExecutor), three author stages, side-by-side workspace, version lane, accept/reject, settings.

- [ ] **Step 2:** Update `ai/current-task.md`: mark sub-project 3 done; note deferred items (template editor UI, checking stages, queue, full Semantics entity, remarks panel, token cost); set next step to sub-project 4.

- [ ] **Step 3: Commit**

```bash
git add ai/current-task.md ai/changelog.md
git commit -m "docs: finish Generation Core sub-project — update task memory"
```

---

## Self-Review

**Spec coverage (design doc §-by-§):**
- Technical decisions (OpenAI, Keychain, streaming, gpt-4.1, layered) → Tasks 11-15. ✓
- ArticleVersion / GenerationJob / StageTemplate → Tasks 2,3,4. ✓
- Topic additions → Task 5. ✓
- KeychainService / PromptBuilder / OpenAIClient / StageExecutor → Tasks 11,6,12,13. ✓
- Stages draft/productBlocks/semanticsInText → Tasks 14 (templates) + 16,21 (run). ✓
- VersionLaneView / SideBySideView / AcceptRejectBar / JobLogView / SettingsView → Tasks 19,17,18,20,15. ✓
- Diff algorithm → Task 7. ✓
- Scope boundaries respected (no template editor UI, no checking stages, no queue). ✓
- Testing strategy (unit for services, manual smoke for UI) → followed throughout. ✓
- Added beyond design doc: minimal `Topic.semantics` list + `SemanticsEditorSheet` (needed for semanticsInText, since the full Semantics entity is deferred). Flagged in plan intro and Task 5/21.

**Placeholder scan:** No TBD/TODO. UI "deferred to Task N" notes point to concrete tasks. Build steps note the inter-view dependency (build once at Task 21).

**Type consistency:** `PipelineStage`, `VersionSource`, `JobStatus`, `ArticleVersion.uuid`, `Topic.currentVersionID`, `StageExecutor.StreamProvider` signature `(apiKey, system, user, model, temperature, maxTokens)`, `StageExecutor.live(model:)`, `ParagraphDiff.newSide/diff/paragraphs`, `VersionActions.assembleHybrid(old:new:acceptedNewIndices:)`, `StageOutputParser.parse(rawText:stage:)`, `OpenAILineParser.parse(line:)`, `KeychainService.save/loadAPIKey/deleteAPIKey/hasAPIKey` — names are consistent across producer and consumer tasks.

**Known risks (call out at execution):**
- Keychain unit tests need local keychain access (Task 11).
- `URLSession.bytes` + URLProtocol streaming test (Task 12) may need a tweak if chunking differs.
- SwiftData migration on first launch may require local store reset (no production data).
- macOS `Table` double-click handled via `primaryAction:` (Task 16) — verify on the target macOS.
