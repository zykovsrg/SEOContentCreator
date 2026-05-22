# Template Editor (Sub-project 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the «Шаблоны» section's first slice — an editor for the 6 stage prompt templates (system + user prompt, model params), with reset-to-default and a read-only variable reference.

**Architecture:** Extract the seeded template defaults into a pure single source of truth (`StageTemplateDefaults`), used by both the seeder and the new "reset" action. Add a `TemplatesView` (list → editor) that edits the existing `StageTemplate` records in place (bumping `templateVersion`). Past `ArticleVersion` snapshots are unaffected.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing. Builds on sub-projects 3–4.

**Spec:** `docs/superpowers/specs/2026-05-22-template-editor-design.md`.

---

## Conventions (read once)

- **Repo root:** `/Users/zykovsrg/Documents/vibecode/SEOContentCreator`
- **App source root:** `SEOContentCreator/SEOContentCreator/SEOContentCreator/` (`Models/`, `Logic/`, `Views/`)
- **Test root:** `SEOContentCreator/SEOContentCreator/SEOContentCreatorTests/`
- **New files auto-add** to the target (Xcode 16 synchronized groups). No `project.pbxproj` editing.
- **Build:** `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build`
- **All tests:** same `cd`, then `xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests`
- **One test:** append `/StructName/methodName`.
- **Commit from repo root:** `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add … && git commit …`
- Pure logic: `enum`/`struct` + `static`. Tests: Swift Testing (`@Test`/`#expect`).

---

## File Structure

**Logic (`.../Logic/`)**
- Create `StageTemplateDefaults.swift` — `StageTemplateContent` struct + `StageTemplateDefaults.content(for:)` (single source of truth for the 6 default templates).
- Modify `StageTemplateSeeder.swift` — build templates from `StageTemplateDefaults` (no content change).
- Create `TemplateVariables.swift` — static read-only variable reference.

**Views (`.../Views/`)**
- Create `TemplatesView.swift` — section: list of stage templates → `TemplateEditorView` + variable reference.
- Modify `RootView.swift` — show `TemplatesView` for `.templates`.

**Tests (`.../SEOContentCreatorTests/`)**
- Create `StageTemplateDefaultsTests.swift`, `TemplateVariablesTests.swift`.

---

### Task 1: StageTemplateDefaults (single source of truth) + seeder refactor

**Files:**
- Create: `.../Logic/StageTemplateDefaults.swift`
- Modify: `.../Logic/StageTemplateSeeder.swift`
- Test: `.../SEOContentCreatorTests/StageTemplateDefaultsTests.swift`

- [ ] **Step 1: Write the failing test** — `StageTemplateDefaultsTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct StageTemplateDefaultsTests {
    @Test func hasContentForEveryStage() {
        for stage in PipelineStage.allCases {
            let c = StageTemplateDefaults.content(for: stage)
            #expect(!c.systemPrompt.isEmpty)
            #expect(!c.userPromptTemplate.isEmpty)
            #expect(c.modelName == "gpt-4.1")
            #expect(c.temperature == 0.6)
            #expect(c.maxTokens == 8000)
        }
    }

    @Test func authorDraftUsesBriefVariables() {
        #expect(StageTemplateDefaults.content(for: .draft).userPromptTemplate.contains("{{тема}}"))
    }

    @Test func checkingStagesAskForRemarksJSON() {
        #expect(StageTemplateDefaults.content(for: .seoCheck).userPromptTemplate.contains("remarks"))
        #expect(StageTemplateDefaults.content(for: .factCheck).userPromptTemplate.contains("{{база_знаний}}"))
        #expect(StageTemplateDefaults.content(for: .finalReview).userPromptTemplate.contains("remarks"))
    }
}
```

- [ ] **Step 2: Run — expect fail**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateDefaultsTests 2>&1 | tail -8`
Expected: FAIL — "cannot find 'StageTemplateDefaults' in scope".

- [ ] **Step 3: Create `StageTemplateDefaults.swift`**

Define the content struct and a `content(for:)` switch. **Move** each stage's `systemPrompt`, `userPromptTemplate`, `modelName`, `temperature`, `maxTokens` VERBATIM from the current `StageTemplateSeeder.makeTemplate(for:)` into the matching case here. The `.draft` case is shown fully as the transformation pattern; do the same move for `.productBlocks`, `.semanticsInText`, `.seoCheck`, `.factCheck`, `.finalReview` (copy their exact strings from the existing seeder — content must remain identical so seeding is unchanged).

```swift
import Foundation

struct StageTemplateContent {
    var systemPrompt: String
    var userPromptTemplate: String
    var modelName: String = "gpt-4.1"
    var temperature: Double = 0.6
    var maxTokens: Int = 8000
}

enum StageTemplateDefaults {
    static func content(for stage: PipelineStage) -> StageTemplateContent {
        switch stage {
        case .draft:
            return StageTemplateContent(
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
            return StageTemplateContent(
                systemPrompt: <verbatim systemPrompt from seeder .productBlocks>,
                userPromptTemplate: <verbatim userPromptTemplate from seeder .productBlocks>
            )
        case .semanticsInText:
            return StageTemplateContent(
                systemPrompt: <verbatim systemPrompt from seeder .semanticsInText>,
                userPromptTemplate: <verbatim userPromptTemplate from seeder .semanticsInText>
            )
        case .seoCheck:
            return StageTemplateContent(
                systemPrompt: <verbatim systemPrompt from seeder .seoCheck>,
                userPromptTemplate: <verbatim userPromptTemplate from seeder .seoCheck>
            )
        case .factCheck:
            return StageTemplateContent(
                systemPrompt: <verbatim systemPrompt from seeder .factCheck>,
                userPromptTemplate: <verbatim userPromptTemplate from seeder .factCheck>
            )
        case .finalReview:
            return StageTemplateContent(
                systemPrompt: <verbatim systemPrompt from seeder .finalReview>,
                userPromptTemplate: <verbatim userPromptTemplate from seeder .finalReview>
            )
        }
    }
}
```
> Note: `<verbatim … from seeder …>` means copy the exact multi-line string literal currently in `StageTemplateSeeder.makeTemplate` for that case. Do not paraphrase — identical text keeps seeding behavior unchanged.

- [ ] **Step 4: Refactor `StageTemplateSeeder.makeTemplate(for:)`** — replace the whole `makeTemplate(for:)` function body with:

```swift
    private static func makeTemplate(for stage: PipelineStage) -> StageTemplate {
        let c = StageTemplateDefaults.content(for: stage)
        return StageTemplate(
            stage: stage,
            systemPrompt: c.systemPrompt,
            userPromptTemplate: c.userPromptTemplate,
            modelName: c.modelName,
            temperature: c.temperature,
            maxTokens: c.maxTokens
        )
    }
```

- [ ] **Step 5: Run defaults + seeder tests — expect pass**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateDefaultsTests -only-testing:SEOContentCreatorTests/StageTemplateSeederTests 2>&1 | grep -E "(passed|failed|TEST SUCCEEDED|TEST FAILED)" | tail`
Expected: TEST SUCCEEDED (defaults: 3 tests; seeder: 2 tests still green — 6 templates).

- [ ] **Step 6: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift SEOContentCreator/SEOContentCreatorTests/StageTemplateDefaultsTests.swift && git commit -m "refactor: extract stage template defaults to single source of truth"
```

---

### Task 2: TemplateVariables (read-only reference)

**Files:**
- Create: `.../Logic/TemplateVariables.swift`
- Test: `.../SEOContentCreatorTests/TemplateVariablesTests.swift`

- [ ] **Step 1: Write the failing test** — `TemplateVariablesTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct TemplateVariablesTests {
    @Test func includesCoreVariables() {
        let tokens = TemplateVariables.all.map { $0.token }
        #expect(tokens.contains("{{тема}}"))
        #expect(tokens.contains("{{семантика}}"))
        #expect(tokens.contains("{{база_знаний}}"))
        #expect(tokens.contains("{{текущий_текст}}"))
    }

    @Test func everyVariableHasDescriptionAndSource() {
        for v in TemplateVariables.all {
            #expect(!v.description.isEmpty)
            #expect(!v.source.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run — expect fail**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/TemplateVariablesTests 2>&1 | tail -8`
Expected: FAIL — "cannot find 'TemplateVariables' in scope".

- [ ] **Step 3: Create `TemplateVariables.swift`**

```swift
import Foundation

struct TemplateVariable: Identifiable {
    var id: String { token }
    let token: String
    let description: String
    let source: String
}

enum TemplateVariables {
    /// Read-only registry mirroring PromptBuilder substitutions (spec §2.5).
    static let all: [TemplateVariable] = [
        TemplateVariable(token: "{{тема}}", description: "Название темы", source: "Бриф"),
        TemplateVariable(token: "{{тип}}", description: "Тип статьи", source: "Бриф"),
        TemplateVariable(token: "{{объём}}", description: "Целевой объём, знаков", source: "Бриф"),
        TemplateVariable(token: "{{направление}}", description: "Направление (описание/название)", source: "Бриф / База знаний"),
        TemplateVariable(token: "{{врач_данные}}", description: "Данные выбранного врача", source: "База знаний"),
        TemplateVariable(token: "{{преимущества}}", description: "Преимущества клиники (прикреплённые узлы)", source: "База знаний"),
        TemplateVariable(token: "{{источники_направления}}", description: "Приоритетные источники направления", source: "База знаний"),
        TemplateVariable(token: "{{семантика}}", description: "Список ключевых запросов", source: "Семантика"),
        TemplateVariable(token: "{{база_знаний}}", description: "Все прикреплённые узлы (для фактчекинга)", source: "База знаний"),
        TemplateVariable(token: "{{текущий_текст}}", description: "Текст текущей версии", source: "Предыдущая версия")
    ]
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/TemplateVariablesTests 2>&1 | tail -8`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Logic/TemplateVariables.swift SEOContentCreator/SEOContentCreatorTests/TemplateVariablesTests.swift && git commit -m "feat: add read-only template variable reference"
```

---

### Task 3: TemplatesView + TemplateEditorView

**Files:**
- Create: `.../Views/TemplatesView.swift`

- [ ] **Step 1: Write `TemplatesView.swift`**

```swift
import SwiftUI
import SwiftData

struct TemplatesView: View {
    @Query private var templates: [StageTemplate]
    @State private var selectedID: UUID?

    private var sortedTemplates: [StageTemplate] {
        templates.sorted { lhs, rhs in
            order(lhs.stageRaw) < order(rhs.stageRaw)
        }
    }

    private func order(_ raw: String) -> Int {
        PipelineStage.allCases.firstIndex { $0.rawValue == raw } ?? Int.max
    }

    private var selectedTemplate: StageTemplate? {
        templates.first { $0.uuid == selectedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                Section("Промты этапов") {
                    ForEach(sortedTemplates) { t in
                        Text(t.stage?.title ?? t.stageRaw).tag(t.uuid)
                    }
                }
            }
            .frame(width: 240)
            Divider()
            if let t = selectedTemplate {
                TemplateEditorView(template: t).id(t.uuid)
            } else {
                ContentUnavailableView("Выберите этап", systemImage: "doc.text")
            }
        }
        .navigationTitle("Шаблоны")
        .onAppear { if selectedID == nil { selectedID = sortedTemplates.first?.uuid } }
    }
}

private struct TemplateEditorView: View {
    @Bindable var template: StageTemplate

    @State private var system = ""
    @State private var user = ""
    @State private var model = "gpt-4.1"
    @State private var temperature = 0.6
    @State private var maxTokens = 8000
    @State private var showAdvanced = false
    @State private var showVariables = false
    @State private var savedNote: String?

    private let models = ["gpt-4.1", "gpt-4o", "gpt-4o-mini"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(template.stage?.title ?? template.stageRaw).font(.title2).bold()
                Text("Версия шаблона: \(template.templateVersion)")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Системный промт (роль, правила, методичка)").font(.headline)
                TextEditor(text: $system).frame(minHeight: 160).border(.gray.opacity(0.3))

                Text("Пользовательский промт (инструкция с переменными)").font(.headline)
                TextEditor(text: $user).frame(minHeight: 200).border(.gray.opacity(0.3))

                DisclosureGroup("Расширенные", isExpanded: $showAdvanced) {
                    Picker("Модель", selection: $model) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    Stepper("Температура: \(temperature, specifier: "%.1f")",
                            value: $temperature, in: 0...1, step: 0.1)
                    Stepper("Max tokens: \(maxTokens)", value: $maxTokens, in: 1000...16000, step: 1000)
                }

                DisclosureGroup("Переменные {{…}}", isExpanded: $showVariables) {
                    ForEach(TemplateVariables.all) { v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.token).font(.system(.callout, design: .monospaced)).bold()
                            Text("\(v.description) · источник: \(v.source)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    Button("Сбросить к стандартному") { resetToDefault() }
                    Spacer()
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private func load() {
        system = template.systemPrompt
        user = template.userPromptTemplate
        model = template.modelName
        temperature = template.temperature
        maxTokens = template.maxTokens
    }

    private func save() {
        template.systemPrompt = system
        template.userPromptTemplate = user
        template.modelName = model
        template.temperature = temperature
        template.maxTokens = maxTokens
        template.templateVersion += 1
        template.updatedAt = .now
        savedNote = "Сохранено (версия \(template.templateVersion))"
    }

    private func resetToDefault() {
        let c = StageTemplateDefaults.content(for: template.stage ?? .draft)
        system = c.systemPrompt
        user = c.userPromptTemplate
        model = c.modelName
        temperature = c.temperature
        maxTokens = c.maxTokens
        save()
        savedNote = "Сброшено к стандартному"
    }
}
```

- [ ] **Step 2: Build** (after Task 4 wires it in; if building now fails only on RootView usage, proceed to Task 4 then build)

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)" | head`
Expected: BUILD SUCCEEDED (TemplatesView compiles standalone).

- [ ] **Step 3: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift && git commit -m "feat: add templates section with stage prompt editor"
```

---

### Task 4: Wire TemplatesView into RootView

**Files:**
- Modify: `.../Views/RootView.swift`

- [ ] **Step 1: Edit `RootView.swift`** — replace the combined `.queue, .templates` case:

```swift
            case .queue, .templates:
                let section = selection ?? .contentPlan
                ContentUnavailableView(
                    section.title,
                    systemImage: section.symbol,
                    description: Text("Раздел появится в следующем под-проекте.")
                )
```
with:
```swift
            case .templates:
                TemplatesView()
            case .queue:
                let section = selection ?? .contentPlan
                ContentUnavailableView(
                    section.title,
                    systemImage: section.symbol,
                    description: Text("Раздел появится в следующем под-проекте.")
                )
```

- [ ] **Step 2: Build**

Run: `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)" | head`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add SEOContentCreator/SEOContentCreator/Views/RootView.swift && git commit -m "feat: show templates editor in Шаблоны section"
```

---

### Task 5: Full build, tests, smoke

- [ ] **Step 1: Full build** — `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)" | head` → BUILD SUCCEEDED.

- [ ] **Step 2: Full unit suite** — `cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests 2>&1 | grep -E "(failed|TEST SUCCEEDED|TEST FAILED)" | tail -5` → TEST SUCCEEDED.

- [ ] **Step 3: Smoke**
1. Run app (Cmd+R). Sidebar → «Шаблоны».
2. Select «Черновик» → edit the user prompt (e.g., add a line) → «Сохранить» → note "Сохранено (версия 2)".
3. Open a topic → run «Черновик» → confirm the generated draft reflects the edited prompt.
4. Back in «Шаблоны» → «Черновик» → «Сбросить к стандартному» → the prompt returns to the original text.
5. Expand «Расширенные» → change model/temperature → save. Expand «Переменные» → see the reference list.

- [ ] **Step 4: Commit (if smoke fixes)** — otherwise skip.

---

### Task 6: Update task memory

**Files:**
- Modify: `ai/current-task.md`, `ai/changelog.md`

- [ ] **Step 1:** Changelog entry (2026-05-22): sub-project 5 — template editor (edit 6 stage prompts + model params, reset-to-default, variable reference; defaults extracted to single source of truth).
- [ ] **Step 2:** `current-task.md`: mark sub-project 5 done; note remaining «Шаблоны» slices (B agents, C types, D blocks, E skills/sandbox); set next.
- [ ] **Step 3: Commit**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator && git add ai/current-task.md ai/changelog.md && git commit -m "docs: finish template-editor sub-project — update task memory"
```

---

## Self-Review

**Spec coverage:**
- §3 edits system/user prompt + model params → Task 3 (TemplateEditorView). ✓
- §4 StageTemplateDefaults (single source) + seeder refactor → Task 1. ✓
- §4 TemplateVariable reference → Task 2 + shown in Task 3. ✓
- §4 TemplatesView + RootView wiring → Tasks 3, 4. ✓
- §2 in-place save (version++) + reset-to-default → Task 3 (`save`, `resetToDefault`). ✓
- §5 testing (defaults coverage, variables, seeder green) → Tasks 1, 2 + Task 5 smoke. ✓
- §7 scope (no history/restore, no agents/types/blocks/skills/sandbox, read-only variables) → respected. ✓

**Placeholder scan:** The only deferred content is the "verbatim move" of 5 existing template strings in Task 1 — this is a refactor move of code already in the repo (source named exactly: `StageTemplateSeeder.makeTemplate`), with the `.draft` case shown fully as the pattern. Not a content placeholder. No other TBD/TODO.

**Type consistency:** `StageTemplateContent{systemPrompt,userPromptTemplate,modelName,temperature,maxTokens}`; `StageTemplateDefaults.content(for:)`; `TemplateVariable{token,description,source}`/`TemplateVariables.all`; `TemplatesView`/`TemplateEditorView`; `StageTemplate` fields (`systemPrompt`,`userPromptTemplate`,`modelName`,`temperature`,`maxTokens`,`templateVersion`,`updatedAt`,`stage`) — consistent with sub-project 3 model.

**Known risks:** No schema change (no store reset needed). Editing TextEditors is local state saved on «Сохранить» (not autosaved) — intended. Nested layout uses a plain HStack master-detail (avoids the nested-NavigationSplitView quirks seen earlier). `resetToDefault` falls back to `.draft` content only if `stage` is nil (shouldn't happen for seeded templates).
