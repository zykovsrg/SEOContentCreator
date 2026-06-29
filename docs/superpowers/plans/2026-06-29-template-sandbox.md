# Template Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe sandbox button to the stage prompt editor so unsaved prompt edits can be run against an existing topic without saving a template, job, or article version.

**Architecture:** Add a non-persistent `StageExecutor.executeSandbox(...)` path that reuses role context, `PromptBuilder`, OpenAI streaming, warning handling, and existing error messages. Add a focused `TemplateSandboxSheet` for choosing a topic and viewing streamed output. Wire `TemplateEditorView` to pass its current local editor state into the sheet as a temporary unsaved `StageTemplate`.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`), macOS. Use `xcodebuild build-for-testing` for CLI verification; full UI smoke is manual in Xcode.

Spec: `docs/superpowers/specs/2026-06-29-template-sandbox-design.md`

---

## File Structure

- Modify `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift` — add the non-persistent sandbox executor method.
- Modify `SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift` — add focused tests for sandbox persistence and unsaved prompt forwarding.
- Create `SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift` — sheet for topic selection, run button, streamed output, errors, and warnings.
- Modify `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift` — add sheet state, sandbox button, and temporary template construction inside `TemplateEditorView`.

No SwiftData model or schema change is planned.

---

### Task 1: Add failing sandbox executor tests

**Files:**
- Modify: `SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift`

- [ ] **Step 1: Add a test that sandbox uses unsaved prompt fields and does not persist**

Append this test inside `StageExecutorTests`:

```swift
    @Test func sandboxUsesTemporaryTemplateWithoutPersisting() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let current = ArticleVersion(stage: .draft, source: .generated, text: "Текущий текст")
        current.topic = topic
        context.insert(current)
        topic.currentVersionID = current.uuid

        let template = StageTemplate(
            stage: .draft,
            systemPrompt: "Временная система",
            userPromptTemplate: "UNSAVED {{тема}} / {{текущий_текст}}",
            modelName: "gpt-5.5",
            temperature: 0.4,
            maxTokens: 3000,
            reasoningEffort: "high"
        )

        var capturedSystem = ""
        var capturedUser = ""
        var capturedReasoning: String?
        let provider: StageExecutor.StreamProvider = { _, system, user, _, _, _, reasoningEffort in
            capturedSystem = system
            capturedUser = user
            capturedReasoning = reasoningEffort
            return AsyncThrowingStream { continuation in
                continuation.yield(.token("Песочный результат"))
                continuation.finish()
            }
        }
        let executor = StageExecutor(streamProvider: provider, keyProvider: { "k" })

        await executor.executeSandbox(
            stage: .draft,
            topic: topic,
            template: template,
            currentText: topic.currentVersion?.text,
            in: context
        )

        #expect(capturedSystem == "Временная система")
        #expect(capturedUser == "UNSAVED Тема / Текущий текст")
        #expect(capturedReasoning == "high")
        #expect(executor.streamingText == "Песочный результат")
        #expect(executor.lastErrorMessage == nil)
        #expect(topic.jobs.isEmpty)
        #expect(topic.versions.count == 1)
        #expect(topic.currentVersionID == current.uuid)
    }
```

- [ ] **Step 2: Add a test for truncation warning without persistence**

Append this test inside `StageExecutorTests`:

```swift
    @Test func sandboxSetsTruncationWarningWithoutPersisting() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let template = StageTemplate(stage: .draft, systemPrompt: "s", userPromptTemplate: "{{тема}}")
        let provider: StageExecutor.StreamProvider = { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.token("Обрезанный песочный текст"))
                continuation.yield(.finish(reason: "length"))
                continuation.finish()
            }
        }
        let executor = StageExecutor(streamProvider: provider, keyProvider: { "k" })

        await executor.executeSandbox(
            stage: .draft,
            topic: topic,
            template: template,
            currentText: nil,
            in: context
        )

        #expect(executor.streamingText == "Обрезанный песочный текст")
        #expect(executor.lastWarningMessage != nil)
        #expect(topic.jobs.isEmpty)
        #expect(topic.versions.isEmpty)
        #expect(topic.currentVersionID == nil)
    }
```

- [ ] **Step 3: Add a test that checking stages can parse remarks without saving**

Append this test inside `StageExecutorTests`:

```swift
    @Test func sandboxCheckingStageParsesRemarksWithoutPersisting() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let template = StageTemplate(stage: .finalReview, systemPrompt: "s", userPromptTemplate: "{{текущий_текст}}")
        let json = #"{"remarks":[{"category":"Язык","quote":"плохо","suggestion":"лучше","explanation":"яснее"}]}"#
        let executor = StageExecutor(streamProvider: cannedStream([json]), keyProvider: { "k" })

        await executor.executeSandbox(
            stage: .finalReview,
            topic: topic,
            template: template,
            currentText: "плохо",
            in: context
        )

        #expect(executor.streamingText == json)
        #expect(executor.remarks.count == 1)
        #expect(executor.remarks.first?.suggestion == "лучше")
        #expect(topic.jobs.isEmpty)
        #expect(topic.versions.isEmpty)
    }
```

- [ ] **Step 4: Run tests and confirm the expected failure**

Run:

```bash
cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build-for-testing
```

Expected: build fails because `StageExecutor` has no member `executeSandbox`.

- [ ] **Step 5: Commit the failing tests only if project practice allows red commits**

Prefer not to commit red tests unless the user explicitly wants strict red/green history. If committing:

```bash
git add SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift
git commit -m "test: cover template sandbox executor"
```

---

### Task 2: Implement non-persistent `executeSandbox`

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift`

- [ ] **Step 1: Add `executeSandbox` to `StageExecutor`**

Insert this method after `execute(...)` and before `executeQuickCheck(...)`:

```swift
    /// Runs a stage template against an existing topic without persisting anything.
    /// Intended for the stage prompt sandbox in Templates.
    func executeSandbox(
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
        lastWarningMessage = nil
        lastResultVersionID = nil
        remarks = []

        let role = fetchRole(for: stage, in: context)
        do {
            let key = try keyProvider()
            let roleContext = buildRoleContext(for: role, in: context)
            let prompt = PromptBuilder().build(
                template: template,
                topic: topic,
                currentText: currentText,
                selectedBlocks: selectedBlocks,
                roleContext: roleContext
            )
            var collected = ""
            var truncated = false
            for try await event in streamProvider(
                key,
                prompt.system,
                prompt.user,
                template.modelName,
                template.temperature,
                template.maxTokens,
                template.reasoningEffort
            ) {
                switch event {
                case .token(let t):
                    collected += t
                    streamingText = collected
                case .finish(let reason):
                    if reason == "length" { truncated = true }
                }
            }
            if truncated {
                lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
            }
            if stage.kind == .checking {
                remarks = RemarksParser.parse(rawText: collected)
            }
        } catch {
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            lastErrorMessage = message
        }

        isRunning = false
    }
```

- [ ] **Step 2: Run the focused build/test check**

Run:

```bash
cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

- [ ] **Step 3: Commit executor and tests**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift
git commit -m "feat: add non-persistent template sandbox executor"
```

---

### Task 3: Add `TemplateSandboxSheet`

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift`

- [ ] **Step 1: Create the sheet file**

Create `SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift`:

```swift
import SwiftUI
import SwiftData

struct TemplateSandboxSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Topic.updatedAt, order: .reverse) private var topics: [Topic]

    let stage: PipelineStage
    let template: StageTemplate

    @State private var selectedTopicID: PersistentIdentifier?
    @State private var executor: StageExecutor?

    private var selectedTopic: Topic? {
        if let selectedTopicID {
            return topics.first { $0.persistentModelID == selectedTopicID }
        }
        return topics.first
    }

    private var isRunning: Bool {
        executor?.isRunning ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Песочница")
                        .font(.title2)
                        .bold()
                    Text(stage.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Закрыть") { dismiss() }
            }

            if topics.isEmpty {
                ContentUnavailableView(
                    "Нет тем для проверки",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Создайте тему в Контент-плане, чтобы запустить песочницу.")
                )
            } else {
                Picker("Тема", selection: topicSelectionBinding) {
                    ForEach(topics) { topic in
                        Text(topic.title).tag(Optional(topic.persistentModelID))
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)

                if let topic = selectedTopic {
                    topicPreview(topic)
                }

                HStack {
                    Button("Запустить") { run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedTopic == nil || isRunning)
                    if isRunning {
                        ProgressView().controlSize(.small)
                    }
                    if let message = executor?.lastErrorMessage {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }

                if let warning = executor?.lastWarningMessage {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }

                Text("Результат").font(.headline)
                ScrollView {
                    Text(executor?.streamingText.isEmpty == false ? executor?.streamingText ?? "" : "Результат появится здесь после запуска.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: 260)
                .border(.gray.opacity(0.3))
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 560)
        .onAppear {
            selectedTopicID = selectedTopicID ?? topics.first?.persistentModelID
        }
    }

    private var topicSelectionBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedTopicID ?? topics.first?.persistentModelID },
            set: { selectedTopicID = $0 }
        )
    }

    private func topicPreview(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(topic.articleType.title) · \(topic.direction?.title ?? "—")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(topic.currentVersion == nil ? "Текущего текста нет" : "Есть текущий текст")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func run() {
        guard let topic = selectedTopic else { return }
        let exec = StageExecutor.live(model: template.modelName)
        executor = exec
        Task {
            await exec.executeSandbox(
                stage: stage,
                topic: topic,
                template: template,
                currentText: topic.currentVersion?.text,
                in: context
            )
        }
    }
}
```

- [ ] **Step 2: Build to catch SwiftUI/type errors**

Run:

```bash
cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

If the build reports `cannot find 'TemplateSandboxSheet' in scope` after Task 4, verify that `SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift` exists at that exact path. Do not manually edit the Xcode project unless Xcode file-system sync failed to include the new Swift file in the app target.

---

### Task 4: Wire sandbox button into `TemplateEditorView`

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift`
- Uses: `SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift`

- [ ] **Step 1: Add sheet state**

Inside `TemplateEditorView`, near the existing `@State` properties, add:

```swift
    @State private var showSandbox = false
```

- [ ] **Step 2: Add the sandbox button**

Change the bottom button row from:

```swift
                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    Button("Сбросить к стандартному") { resetToDefault() }
                    Spacer()
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
```

to:

```swift
                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    Button("Песочница") { showSandbox = true }
                    Button("Сбросить к стандартному") { resetToDefault() }
                    Spacer()
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
```

- [ ] **Step 3: Present `TemplateSandboxSheet` with a temporary template**

At the end of the `ScrollView` chain in `TemplateEditorView.body`, after `.onAppear(perform: load)`, add:

```swift
        .sheet(isPresented: $showSandbox) {
            TemplateSandboxSheet(
                stage: template.stage ?? .draft,
                template: sandboxTemplate()
            )
        }
```

- [ ] **Step 4: Add `sandboxTemplate()` helper**

Inside `TemplateEditorView`, after `resetToDefault()`, add:

```swift
    private func sandboxTemplate() -> StageTemplate {
        StageTemplate(
            stage: template.stage ?? .draft,
            articleType: template.articleTypeRaw.flatMap(ArticleType.init(rawValue:)),
            systemPrompt: system,
            userPromptTemplate: user,
            modelName: model,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoningEffort: (OpenAIClient.usesMaxCompletionTokens(model: model) && !reasoningEffort.isEmpty)
                ? reasoningEffort
                : nil,
            templateVersion: template.templateVersion
        )
    }
```

- [ ] **Step 5: Build and fix any compile issue**

Run:

```bash
cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

- [ ] **Step 6: Commit UI wiring**

```bash
git add SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift
git commit -m "feat: add template sandbox sheet"
```

---

### Task 5: Verification and manual smoke

**Files:**
- Read/check: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift`
- Read/check: `SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift`
- Read/check: `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift`

- [ ] **Step 1: Run automated verification**

Run:

```bash
cd SEOContentCreator && xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

- [ ] **Step 2: Inspect changed files**

Run:

```bash
git diff --name-only
```

Expected changed implementation files:

```text
SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift
SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift
SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift
SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift
```

It is acceptable for `ai/current-task.md` to remain modified during active work. Existing Xcode user-state changes are unrelated and must not be committed.

- [ ] **Step 3: Manual UI smoke in Xcode**

Open `SEOContentCreator/SEOContentCreator.xcodeproj` in Xcode and run Cmd+R.

Manual checklist:

- Open "Шаблоны".
- Select a stage prompt under "Промты этапов".
- Edit the user prompt text but do not click "Сохранить".
- Click "Песочница".
- Choose a topic.
- Click "Запустить".
- Confirm output streams into the result area.
- Close the sheet.
- Confirm the template version shown in the editor did not increment.
- Open the tested topic and confirm no new version appeared in the version lane.
- Open the topic log and confirm no sandbox job was added.

- [ ] **Step 4: Final commit if any fixes were needed**

If verification fixes changed files after Task 4, commit them:

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift SEOContentCreator/SEOContentCreator/Views/TemplateSandboxSheet.swift SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift
git commit -m "fix: polish template sandbox"
```

---

## Self-Review

Spec coverage:

- Sandbox entry point in stage prompt editor: Task 4.
- Uses current unsaved editor fields: Task 4 `sandboxTemplate()` and Task 1 captured prompt test.
- Selected existing topic as input: Task 3 topic picker.
- Streamed output, errors, warnings: Task 2 executor state and Task 3 UI.
- No `GenerationJob`, `ArticleVersion`, or `currentVersionID` mutation: Task 1 tests and Task 2 implementation.
- Focused tests: Task 1 and Task 2.

No import/export, product block sandboxing, skill sandboxing, backup, saving sandbox output, or accept/reject flow is included.
