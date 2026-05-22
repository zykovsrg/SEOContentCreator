# Checking Stages (Sub-project 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three checking stages (Проверка SEO, Фактчекинг, Финальная вычитка) that return per-remark suggestion cards the editor accepts pointwise, producing one new version on "Готово".

**Architecture:** Reuse the generation core (StageExecutor, version lane, log, streaming, settings). Checking stages return a JSON list of remarks (not a rewrite); a transient remark list drives a cards panel; accepting cards applies `quote→suggestion` to a live working copy; "Готово" creates one `ArticleVersion`. Methodics are seeded into checking-stage prompts (editing deferred to a later "Шаблоны" sub-project).

**Tech Stack:** SwiftUI, SwiftData, Swift structured concurrency, Swift Testing. Builds on sub-project 3.

**Spec:** `docs/superpowers/specs/2026-05-22-checking-stages-design.md`.

---

## Conventions (read once)

- **Repo root:** `/Users/zykovsrg/Documents/vibecode/SEOContentCreator`
- **App source root:** `SEOContentCreator/SEOContentCreator/SEOContentCreator/` (folders `Models/`, `Logic/`, `Views/`)
- **Test root:** `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/`
- **New files auto-add** to the target (Xcode 16 synchronized groups). No `project.pbxproj` editing.
- **Build:** `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
- **All tests:** same `cd`, then `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests`
- **One test:** append `/StructName/methodName`.
- **Commit from repo root:** `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add … && git commit …`
- **Enum convention:** store `xxxRaw: String`, computed bridge. **Pure logic:** `enum`/`struct` + `static func`. **Tests:** Swift Testing (`@Test`/`#expect`).

---

## File Structure

**Models (`.../Models/`)**
- Modify `PipelineStage.swift` — add `seoCheck`/`factCheck`/`finalReview`, `StageKind`, per-stage `agentName`.
- Modify `VersionSource.swift` — add `checkApplied`.

**Logic (`.../Logic/`)**
- Create `Remark.swift` — transient remark struct + `RemarksParser`.
- Create `RemarkApplier.swift` — apply accepted remarks to text (pure).
- Modify `PromptBuilder.swift` — add `{{база_знаний}}`.
- Modify `StageExecutor.swift` — checking branch (remarks, no version) + `remarks` property.
- Modify `StageTemplateSeeder.swift` — add 3 checking templates.

**Views (`.../Views/`)**
- Create `RemarksPanelView.swift` — cards (category, explanation, было→станет, ✓/✗, tap-to-select).
- Create `HighlightedText.swift` — text with a highlighted substring.
- Modify `TopicWorkspaceView.swift` — checking review mode (working copy, accept/reject, Готово).

**Tests (`.../SEOContentCreatorTests/`)**
- Modify `PipelineStageTests.swift`, create `RemarkTests.swift`, `RemarkApplierTests.swift`, modify `PromptBuilderTests.swift`, modify `StageExecutorTests.swift`.

---

# Phase 1 — Models & enums

### Task 1: Extend PipelineStage with checking stages

**Files:**
- Modify: `.../Models/PipelineStage.swift`
- Test: `.../SEOContentCreatorTests/PipelineStageTests.swift`

- [ ] **Step 1: Add the failing test** — append these tests inside `struct PipelineStageTests` (before its closing `}`):

```swift
    @Test func checkingStagesHaveOwnAgents() {
        #expect(PipelineStage.seoCheck.agentName == "ИИ-SEO")
        #expect(PipelineStage.factCheck.agentName == "ИИ-фактчекер")
        #expect(PipelineStage.finalReview.agentName == "ИИ-редактор")
    }

    @Test func stageKindIsClassified() {
        #expect(PipelineStage.draft.kind == .author)
        #expect(PipelineStage.semanticsInText.kind == .author)
        #expect(PipelineStage.seoCheck.kind == .checking)
        #expect(PipelineStage.finalReview.kind == .checking)
    }

    @Test func checkingTitlesAreRussian() {
        #expect(PipelineStage.seoCheck.title == "Проверка SEO")
        #expect(PipelineStage.factCheck.title == "Фактчекинг")
        #expect(PipelineStage.finalReview.title == "Финальная вычитка")
    }
```

- [ ] **Step 2: Run — expect fail**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PipelineStageTests 2>&1 | tail -8`
Expected: FAIL — "type 'PipelineStage' has no member 'seoCheck'".

- [ ] **Step 3: Replace `PipelineStage.swift` entirely with:**

```swift
import Foundation

enum StageKind {
    case author
    case checking
}

enum PipelineStage: String, CaseIterable, Identifiable, Codable {
    case draft
    case productBlocks
    case semanticsInText
    case seoCheck
    case factCheck
    case finalReview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft:           return "Черновик"
        case .productBlocks:   return "Продуктовые блоки"
        case .semanticsInText: return "Семантика-в-текст"
        case .seoCheck:        return "Проверка SEO"
        case .factCheck:       return "Фактчекинг"
        case .finalReview:     return "Финальная вычитка"
        }
    }

    var kind: StageKind {
        switch self {
        case .draft, .productBlocks, .semanticsInText: return .author
        case .seoCheck, .factCheck, .finalReview:      return .checking
        }
    }

    var agentName: String {
        switch self {
        case .draft, .productBlocks, .semanticsInText: return "ИИ-автор"
        case .seoCheck:    return "ИИ-SEO"
        case .factCheck:   return "ИИ-фактчекер"
        case .finalReview: return "ИИ-редактор"
        }
    }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PipelineStageTests 2>&1 | tail -8`
Expected: PASS (existing + 3 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Models/PipelineStage.swift SEOContentCreator/SEOContentCreatorTests/PipelineStageTests.swift && git commit -m "feat: add checking stages and stage kind to PipelineStage"
```

---

### Task 2: Add checkApplied to VersionSource

**Files:**
- Modify: `.../Models/VersionSource.swift`

- [ ] **Step 1: Edit `VersionSource.swift`** — add the case after `case importFromDocs`:

```swift
    case checkApplied
```
and add to the `title` switch (after the `.importFromDocs` line):
```swift
        case .checkApplied:    return "Правки проверки"
```

- [ ] **Step 2: Build**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)" | head`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Models/VersionSource.swift && git commit -m "feat: add checkApplied version source"
```

---

# Phase 2 — Pure logic

### Task 3: Remark struct + RemarksParser

**Files:**
- Create: `.../Logic/Remark.swift`
- Test: `.../SEOContentCreatorTests/RemarkTests.swift`

- [ ] **Step 1: Write the failing test** — `RemarkTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct RemarkTests {
    @Test func parsesRemarksFromFencedJSON() {
        let raw = """
        Вот замечания:
        ```json
        {"remarks":[{"category":"Канцелярит","quote":"осуществляется","suggestion":"делается","explanation":"проще"}]}
        ```
        """
        let remarks = RemarksParser.parse(rawText: raw)
        #expect(remarks.count == 1)
        #expect(remarks.first?.category == "Канцелярит")
        #expect(remarks.first?.quote == "осуществляется")
        #expect(remarks.first?.suggestion == "делается")
        #expect(remarks.first?.explanation == "проще")
    }

    @Test func parsesRawJSONObject() {
        let raw = #"{"remarks":[{"category":"Факт","quote":"5000","suggestion":"4500","explanation":"в справочнике 4500"}]}"#
        let remarks = RemarksParser.parse(rawText: raw)
        #expect(remarks.count == 1)
        #expect(remarks.first?.suggestion == "4500")
    }

    @Test func brokenOrEmptyReturnsEmpty() {
        #expect(RemarksParser.parse(rawText: "нет json").isEmpty)
        #expect(RemarksParser.parse(rawText: "").isEmpty)
        #expect(RemarksParser.parse(rawText: #"{"remarks": "не массив"}"#).isEmpty)
    }

    @Test func eachRemarkGetsUniqueID() {
        let raw = #"{"remarks":[{"category":"A","quote":"x","suggestion":"y","explanation":"e"},{"category":"B","quote":"z","suggestion":"w","explanation":"e2"}]}"#
        let remarks = RemarksParser.parse(rawText: raw)
        #expect(remarks.count == 2)
        #expect(remarks[0].id != remarks[1].id)
    }
}
```

- [ ] **Step 2: Run — expect fail**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/RemarkTests 2>&1 | tail -8`
Expected: FAIL — "cannot find 'RemarksParser' in scope".

- [ ] **Step 3: Write `Remark.swift`:**

```swift
import Foundation

struct Remark: Codable, Identifiable {
    var id = UUID()
    var category: String
    var quote: String
    var suggestion: String
    var explanation: String

    enum CodingKeys: String, CodingKey {
        case category, quote, suggestion, explanation
    }
}

enum RemarksParser {
    private struct Wrapper: Codable { let remarks: [Remark] }

    /// Extracts a JSON object (from a ```json fence or the first {...}) and decodes `{"remarks":[…]}`.
    /// Returns [] on missing or malformed JSON.
    static func parse(rawText: String) -> [Remark] {
        guard let json = extractJSON(from: rawText),
              let data = json.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data)
        else { return [] }
        return wrapper.remarks
    }

    private static func extractJSON(from text: String) -> String? {
        if let fence = text.range(of: "```json"),
           let end = text.range(of: "```", range: fence.upperBound..<text.endIndex) {
            return String(text[fence.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last {
            return String(text[first...last])
        }
        return nil
    }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/RemarkTests 2>&1 | tail -8`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Logic/Remark.swift SEOContentCreator/SEOContentCreatorTests/RemarkTests.swift && git commit -m "feat: add Remark model and RemarksParser"
```

---

### Task 4: RemarkApplier

**Files:**
- Create: `.../Logic/RemarkApplier.swift`
- Test: `.../SEOContentCreatorTests/RemarkApplierTests.swift`

- [ ] **Step 1: Write the failing test** — `RemarkApplierTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct RemarkApplierTests {
    private func remark(_ quote: String, _ suggestion: String) -> Remark {
        Remark(category: "C", quote: quote, suggestion: suggestion, explanation: "e")
    }

    @Test func appliesSingleReplacement() {
        let result = RemarkApplier.apply(base: "abc осуществляется def", accepted: [remark("осуществляется", "делается")])
        #expect(result == "abc делается def")
    }

    @Test func appliesMultipleReplacements() {
        let result = RemarkApplier.apply(
            base: "Цена 5000. Текст водянистый.",
            accepted: [remark("5000", "4500"), remark("водянистый", "ёмкий")]
        )
        #expect(result == "Цена 4500. Текст ёмкий.")
    }

    @Test func notFoundQuoteSkipped() {
        let result = RemarkApplier.apply(base: "abc", accepted: [remark("xyz", "qqq")])
        #expect(result == "abc")
    }

    @Test func emptyAcceptedReturnsBase() {
        #expect(RemarkApplier.apply(base: "abc", accepted: []) == "abc")
    }

    @Test func emptyQuoteSkipped() {
        #expect(RemarkApplier.apply(base: "abc", accepted: [remark("", "qqq")]) == "abc")
    }
}
```

- [ ] **Step 2: Run — expect fail**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/RemarkApplierTests 2>&1 | tail -8`
Expected: FAIL — "cannot find 'RemarkApplier' in scope".

- [ ] **Step 3: Write `RemarkApplier.swift`:**

```swift
import Foundation

enum RemarkApplier {
    /// Applies accepted remarks to `base` by replacing the first remaining occurrence of each
    /// non-empty `quote` with its `suggestion`, in the given order. Quotes not found are skipped.
    static func apply(base: String, accepted: [Remark]) -> String {
        var result = base
        for remark in accepted where !remark.quote.isEmpty {
            if let range = result.range(of: remark.quote) {
                result.replaceSubrange(range, with: remark.suggestion)
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/RemarkApplierTests 2>&1 | tail -8`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Logic/RemarkApplier.swift SEOContentCreator/SEOContentCreatorTests/RemarkApplierTests.swift && git commit -m "feat: add RemarkApplier for pointwise edits"
```

---

### Task 5: PromptBuilder — add {{база_знаний}}

**Files:**
- Modify: `.../Logic/PromptBuilder.swift`
- Test: `.../SEOContentCreatorTests/PromptBuilderTests.swift`

- [ ] **Step 1: Add the failing test** — append inside `struct PromptBuilderTests` (before its closing `}`):

```swift
    @Test func substitutesKnowledgeBase() {
        let t = StageTemplate(stage: .factCheck, systemPrompt: "x",
                              userPromptTemplate: "Справочник:\n{{база_знаний}}")
        let topic = Topic(title: "T", articleType: .disease)
        let adv = KnowledgeNode(title: "Преимущество", type: .advantage, content: "Лечение за один визит")
        let doc = KnowledgeNode(title: "Усычкин С.В.", type: .doctor, content: "Стаж 20 лет")
        topic.attachedNodes = [adv, doc]
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "текст")
        #expect(result.user.contains("Лечение за один визит"))
        #expect(result.user.contains("Усычкин С.В.: Стаж 20 лет"))
    }
```

- [ ] **Step 2: Run — expect fail**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptBuilderTests 2>&1 | tail -8`
Expected: FAIL — `{{база_знаний}}` left literal, assertion fails.

- [ ] **Step 3: Edit `PromptBuilder.swift`** — after the line `let semantics = topic.semantics.joined(separator: "\n")` add:

```swift
        let knowledge = topic.attachedNodes.map { node in
            node.content.isEmpty ? node.title : "\(node.title): \(node.content)"
        }.joined(separator: "\n")
```
and add this entry to the `substitutions` dictionary (after the `"{{семантика}}": semantics,` line):
```swift
            "{{база_знаний}}": knowledge,
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptBuilderTests 2>&1 | tail -8`
Expected: PASS (existing + 1 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift && git commit -m "feat: add knowledge-base variable to PromptBuilder"
```

---

# Phase 3 — Services

### Task 6: StageExecutor — checking branch

**Files:**
- Modify: `.../Logic/StageExecutor.swift`
- Test: `.../SEOContentCreatorTests/StageExecutorTests.swift`

- [ ] **Step 1: Add the failing test** — append inside `struct StageExecutorTests` (before its closing `}`):

```swift
    @Test func checkingStagePopulatesRemarksNoVersion() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let template = StageTemplate(stage: .finalReview, systemPrompt: "s", userPromptTemplate: "{{текущий_текст}}")
        context.insert(template)

        let json = #"{"remarks":[{"category":"Орфография","quote":"тест","suggestion":"текст","explanation":"опечатка"}]}"#
        let executor = StageExecutor(streamProvider: cannedStream([json]), keyProvider: { "k" })
        await executor.execute(stage: .finalReview, topic: topic, template: template,
                               currentText: "тест", in: context)

        #expect(executor.remarks.count == 1)
        #expect(executor.remarks.first?.category == "Орфография")
        #expect(topic.currentVersion == nil)         // checking creates no version
        #expect(executor.lastResultVersionID == nil)
        #expect(topic.jobs.first?.status == .success)
    }
```

- [ ] **Step 2: Run — expect fail**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageExecutorTests 2>&1 | tail -8`
Expected: FAIL — "value of type 'StageExecutor' has no member 'remarks'".

- [ ] **Step 3: Edit `StageExecutor.swift`:**

Add property after `var lastResultVersionID: UUID?`:
```swift
    /// Transient remarks from the most recent checking run (not persisted).
    var remarks: [Remark] = []
```
In `execute(...)`, after the line `lastResultVersionID = nil` add:
```swift
        remarks = []
```
Replace the success block that currently builds the version. Find:
```swift
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

            topic.updatedAt = .now

            job.status = .success
            job.finishedAt = .now
            job.resultVersionID = version.uuid
            lastResultVersionID = version.uuid
```
with:
```swift
            if stage.kind == .checking {
                remarks = RemarksParser.parse(rawText: collected)
                job.status = .success
                job.finishedAt = .now
            } else {
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

                topic.updatedAt = .now

                job.status = .success
                job.finishedAt = .now
                job.resultVersionID = version.uuid
                lastResultVersionID = version.uuid
            }
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageExecutorTests 2>&1 | tail -8`
Expected: PASS (existing 2 + 1 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift && git commit -m "feat: StageExecutor produces remarks for checking stages"
```

---

### Task 7: StageTemplateSeeder — 3 checking templates

**Files:**
- Modify: `.../Logic/StageTemplateSeeder.swift`
- Test: `.../SEOContentCreatorTests/StageTemplateSeederTests.swift` (no change needed — `seedsOneTemplatePerStage` already asserts `count == PipelineStage.allCases.count`, now 6)

- [ ] **Step 1: Run existing seeder test — expect fail**

Because `makeTemplate(for:)` switch is not exhaustive after adding 3 stages, the file will not compile.
Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateSeederTests 2>&1 | tail -8`
Expected: FAIL — "switch must be exhaustive".

- [ ] **Step 2: Edit `StageTemplateSeeder.swift`** — in `makeTemplate(for:)`, add these three cases before the closing `}` of the `switch stage` (after the `.semanticsInText` case block):

```swift
        case .seoCheck:
            return StageTemplate(
                stage: .seoCheck,
                systemPrompt: """
                Ты — придирчивый SEO-редактор медицинских статей. Твоя задача — не переписывать текст, \
                а найти проблемы и предложить точечные правки. Проверяй: структуру заголовков H1/H2/H3, \
                наличие и естественность ключевых запросов и их плотность, корректность Title и Description \
                (длину), объём, отсутствие рекламных преувеличений. Русский язык. Сомневайся и сверяй.
                """,
                userPromptTemplate: """
                Проверь текст на соответствие SEO-требованиям. Не переписывай — верни список замечаний.

                Текст:
                {{текущий_текст}}

                Ключевые запросы:
                {{семантика}}

                Верни ТОЛЬКО JSON в формате:
                ```json
                {"remarks":[{"category":"...","quote":"<точный фрагмент из текста>","suggestion":"<замена>","explanation":"<что не так и почему>"}]}
                ```
                Категории: «Заголовки», «Ключи», «Title/Description», «Объём», «Рекламность». \
                Поле quote — дословный фрагмент из текста (для поиска). Если правка не нужна, suggestion оставь пустым.
                """
            )
        case .factCheck:
            return StageTemplate(
                stage: .factCheck,
                systemPrompt: """
                Ты — придирчивый медицинский фактчекер. Не переписывай текст — сверяй факты с переданным \
                справочником клиники и опирайся на доказательность. Проверяй имена врачей, названия процедур, \
                цены, числа и проверяемые утверждения. Если факт расходится со справочником — это замечание. \
                Не выдумывай. Русский язык.
                """,
                userPromptTemplate: """
                Сверь факты в тексте со справочником клиники. Не переписывай — верни список замечаний.

                Текст:
                {{текущий_текст}}

                Справочник клиники (База знаний):
                {{база_знаний}}

                Верни ТОЛЬКО JSON в формате:
                ```json
                {"remarks":[{"category":"...","quote":"<точный фрагмент из текста>","suggestion":"<исправление>","explanation":"<расхождение со справочником>"}]}
                ```
                Категории: «Имя врача», «Процедура», «Цена», «Факт». \
                Поле quote — дословный фрагмент из текста. Если правка не нужна, suggestion оставь пустым.
                """
            )
        case .finalReview:
            return StageTemplate(
                stage: .finalReview,
                systemPrompt: """
                Ты — придирчивый литературный редактор-корректор медицинских текстов. Не переписывай весь текст — \
                находи конкретные проблемы и предлагай точечные правки: орфография, грамматика, пунктуация, \
                стиль, канцеляризмы, перегруженные предложения, «вода». Соблюдай редполитику: ясность, \
                доказательная осторожность, без рекламных штампов. Русский язык.
                """,
                userPromptTemplate: """
                Вычитай текст. Не переписывай целиком — верни список точечных замечаний.

                Текст:
                {{текущий_текст}}

                Верни ТОЛЬКО JSON в формате:
                ```json
                {"remarks":[{"category":"...","quote":"<точный фрагмент из текста>","suggestion":"<исправленный фрагмент>","explanation":"<что не так>"}]}
                ```
                Категории: «Орфография», «Грамматика», «Пунктуация», «Стиль», «Канцелярит», «Вода». \
                Поле quote — дословный фрагмент из текста.
                """
            )
```

- [ ] **Step 3: Run — expect pass**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateSeederTests 2>&1 | tail -8`
Expected: PASS (2 tests; now seeds 6 templates).

- [ ] **Step 4: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift && git commit -m "feat: seed SEO/factcheck/final-review templates with methodics"
```

---

# Phase 4 — UI (manual smoke)

> UI is verified by build + running the app. After Task 9 the checking flow is end-to-end. The shared executor is `StageExecutor.live(model:)` (already wired in the workspace).

### Task 8: RemarksPanelView + HighlightedText

**Files:**
- Create: `.../Views/RemarksPanelView.swift`
- Create: `.../Views/HighlightedText.swift`

- [ ] **Step 1: Write `HighlightedText.swift`:**

```swift
import SwiftUI

/// Plain text that highlights the first occurrence of `highlight` (if any).
struct HighlightedText: View {
    var text: String
    var highlight: String?

    var body: some View {
        Text(attributed).textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var a = AttributedString(text)
        if let highlight, !highlight.isEmpty, let range = a.range(of: highlight) {
            a[range].backgroundColor = .yellow.opacity(0.45)
        }
        return a
    }
}
```

- [ ] **Step 2: Write `RemarksPanelView.swift`:**

```swift
import SwiftUI

struct RemarksPanelView: View {
    var remarks: [Remark]
    var acceptedIDs: Set<UUID>
    var rejectedIDs: Set<UUID>
    var onAccept: (Remark) -> Void
    var onReject: (Remark) -> Void
    var onSelect: (Remark) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Замечания: \(remarks.count)").font(.caption).foregroundStyle(.secondary).padding(6)
            Divider()
            if remarks.isEmpty {
                ContentUnavailableView("Замечаний нет", systemImage: "checkmark.seal")
            } else {
                List(remarks) { remark in
                    card(remark)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(remark) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private func card(_ remark: Remark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(remark.category).font(.caption).bold().foregroundStyle(.blue)
            Text(remark.explanation).font(.subheadline)
            if !remark.suggestion.isEmpty {
                Text("было: \(remark.quote)").font(.caption).foregroundStyle(.secondary)
                Text("станет: \(remark.suggestion)").font(.caption).foregroundStyle(.green)
            }
            HStack {
                Button("Принять") { onAccept(remark) }
                    .controlSize(.small).buttonStyle(.borderedProminent)
                    .disabled(acceptedIDs.contains(remark.id))
                Button("Отклонить") { onReject(remark) }
                    .controlSize(.small)
                    .disabled(rejectedIDs.contains(remark.id))
                Spacer()
                if acceptedIDs.contains(remark.id) {
                    Label("принято", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                } else if rejectedIDs.contains(remark.id) {
                    Label("отклонено", systemImage: "xmark").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Build**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)" | head`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Views/RemarksPanelView.swift SEOContentCreator/SEOContentCreator/Views/HighlightedText.swift && git commit -m "feat: add remarks panel and highlighted text views"
```

---

### Task 9: TopicWorkspaceView — checking review mode

**Files:**
- Modify: `.../Views/TopicWorkspaceView.swift`

- [ ] **Step 1: Add review state** — after the line `@State private var pendingVersionID: UUID?` add:

```swift
    @State private var acceptedRemarkIDs: Set<UUID> = []
    @State private var rejectedRemarkIDs: Set<UUID> = []
    @State private var highlightedQuote: String?
```

- [ ] **Step 2: Branch the body** — replace this block in `body`:

```swift
            SideBySideView(
                leftText: comparisonText ?? topic.currentVersion?.text,
                rightText: rightText,
                isStreaming: executor?.isRunning ?? false
            )
            Divider()
            AcceptRejectBar(
                canAct: pendingVersion != nil && !(executor?.isRunning ?? false),
                onAcceptAll: acceptAll,
                onAcceptPartial: { showPartialAccept = true },
                onReject: reject
            )
```
with:
```swift
            if isReviewing {
                HStack(spacing: 0) {
                    ScrollView {
                        HighlightedText(text: workingCopy, highlight: highlightedQuote)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    Divider()
                    RemarksPanelView(
                        remarks: executor?.remarks ?? [],
                        acceptedIDs: acceptedRemarkIDs,
                        rejectedIDs: rejectedRemarkIDs,
                        onAccept: { acceptedRemarkIDs.insert($0.id); rejectedRemarkIDs.remove($0.id) },
                        onReject: { rejectedRemarkIDs.insert($0.id); acceptedRemarkIDs.remove($0.id) },
                        onSelect: { highlightedQuote = $0.quote }
                    )
                    .frame(width: 340)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Отклонить всё", role: .destructive) { endReview() }
                    Button("Готово") { finishReview() }.keyboardShortcut(.defaultAction)
                }
                .padding(8)
            } else {
                SideBySideView(
                    leftText: comparisonText ?? topic.currentVersion?.text,
                    rightText: rightText,
                    isStreaming: executor?.isRunning ?? false
                )
                Divider()
                AcceptRejectBar(
                    canAct: pendingVersion != nil && !(executor?.isRunning ?? false),
                    onAcceptAll: acceptAll,
                    onAcceptPartial: { showPartialAccept = true },
                    onReject: reject
                )
            }
```

- [ ] **Step 3: Add computed helpers** — after the `pendingVersion` computed property add:

```swift
    private var isReviewing: Bool {
        !(executor?.remarks.isEmpty ?? true)
    }

    private var reviewBaseText: String {
        topic.currentVersion?.text ?? ""
    }

    private var workingCopy: String {
        let accepted = (executor?.remarks ?? []).filter { acceptedRemarkIDs.contains($0.id) }
        return RemarkApplier.apply(base: reviewBaseText, accepted: accepted)
    }
```

- [ ] **Step 4: Reset review state on run** — in `runStage(_:blocks:)`, after the line `pendingVersionID = nil` (the one before `let template = …`) add:

```swift
        acceptedRemarkIDs = []
        rejectedRemarkIDs = []
        highlightedQuote = nil
```

- [ ] **Step 5: Add review actions** — after the `applyPartial(...)` method add:

```swift
    private func finishReview() {
        let base = reviewBaseText
        let accepted = (executor?.remarks ?? []).filter { acceptedRemarkIDs.contains($0.id) }
        let result = RemarkApplier.apply(base: base, accepted: accepted)
        if result != base {
            let version = ArticleVersion(stage: selectedStage, source: .checkApplied, text: result)
            version.topic = topic
            context.insert(version)
            topic.currentVersionID = version.uuid
            topic.updatedAt = .now
        }
        endReview()
    }

    private func endReview() {
        executor?.remarks = []
        acceptedRemarkIDs = []
        rejectedRemarkIDs = []
        highlightedQuote = nil
    }
```

- [ ] **Step 6: Build**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)" | head`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift && git commit -m "feat: checking review mode in topic workspace (cards, live edits, Готово)"
```

---

### Task 10: Full build, tests, smoke

- [ ] **Step 1: Full build**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)" | head`
Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Full unit suite**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests 2>&1 | grep -E "(failed|TEST SUCCEEDED|TEST FAILED)" | tail -5`
Expected: TEST SUCCEEDED.

- [ ] **Step 3: End-to-end smoke (real API)**

1. Run the app (Cmd+R). Templates re-seed (now 6).
2. Open a topic that already has a current version (or generate a draft and accept it).
3. Stage bar → «Финальная вычитка» → «Запустить этап». After streaming, the right panel shows remark cards.
4. Click a card → its fragment highlights in the left text.
5. «Принять» on a few cards → the left working copy updates live.
6. «Готово» → one new version «Правки проверки» appears in «Версии»; «Лог» shows the run as ✓.
7. Repeat for «Проверка SEO» (needs semantics) and «Фактчекинг» (needs attached knowledge nodes; check it references them).

- [ ] **Step 4: Commit (if any smoke fixes)** — otherwise skip.

---

### Task 11: Update task memory

**Files:**
- Modify: `ai/current-task.md`, `ai/changelog.md`

- [ ] **Step 1:** Add a changelog entry (2026-05-22) for sub-project 4: 3 checking stages, remark cards, pointwise accept, one version on Готово, seeded methodics, knowledge-base variable for factcheck.

- [ ] **Step 2:** Update `current-task.md`: mark sub-project 4 done; note deferred (templates editor, Стиль, publication, full Semantics, queue); set next to sub-project 5.

- [ ] **Step 3: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add ai/current-task.md ai/changelog.md && git commit -m "docs: finish checking-stages sub-project — update task memory"
```

---

## Self-Review

**Spec coverage:**
- §3 stages & agents → Task 1. ✓
- §4 remark format + parser → Task 3. ✓
- §5 checking execution (remarks, no version) + factcheck knowledge base → Tasks 6, 5. ✓
- §6 panel + pointwise accept + live working copy + Готово (one version, none if no edits) → Tasks 8, 9 (`finishReview` skips version when `result == base`). ✓
- §7 entities summary → Tasks 1,2,3,4,5,6,7. ✓
- §8 testing (unit + smoke) → Tasks 1,3,4,5,6,7 (unit) + Task 10 (smoke). ✓
- §9 scope (no templates editor / Стиль / publication) → respected. ✓

**Placeholder scan:** No TBD/TODO. All steps show concrete code or commands.

**Type consistency:** `PipelineStage.kind`/`StageKind`, `agentName` per stage; `VersionSource.checkApplied`; `Remark{category,quote,suggestion,explanation,id}`; `RemarksParser.parse(rawText:)`; `RemarkApplier.apply(base:accepted:)`; `StageExecutor.remarks`; `PromptBuilder` `{{база_знаний}}`; workspace `isReviewing`/`workingCopy`/`finishReview`/`endReview`/`reviewBaseText`/`acceptedRemarkIDs`/`rejectedRemarkIDs`/`highlightedQuote` — consistent across producer/consumer tasks.

**Known risks:** `RemarkApplier` replaces first remaining occurrence — duplicate identical quotes with different intended targets may mis-apply (acceptable v1). Stage bar now shows 6 chips (may wrap on narrow windows). Schema unchanged (no new SwiftData models — no store reset needed). In-text highlight is first-occurrence only.
