# Unified Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two separate "Ручная правка" / "Правка фрагмента" sheets with one "Редактор" sheet where the user freely edits the full article text and, without leaving the screen, selects a fragment and regenerates it via a skill preset or a custom comment, any number of times, before saving once.

**Architecture:** A pure `EditorSessionState` enum (`.editing` / `.generating` / `.reviewing`) drives what's editable and what's clickable. `MarkdownTextEditor` grows the ability to report the current selection (range + on-screen rect) and to temporarily lock editing / highlight a range, without ever converting its plain-text storage to `AttributedString`. `FragmentEditor` drops its old text-search-based splice (`FragmentSplicer`) and version-creation responsibilities — the caller already knows the exact `NSRange` of the selection, so it substitutes the AI's rewritten fragment directly; only the final explicit "Сохранить" creates one `ArticleVersion`, via the existing `VersionActions.applyManualEdit`.

**Tech Stack:** SwiftUI, AppKit (`NSTextView`/`NSLayoutManager`), SwiftData, Swift Testing (`@Test`/`#expect`).

**Design doc:** `docs/superpowers/specs/2026-07-04-unified-editor-design.md`

---

## Task 1: `EditorSessionState` — pure session state machine

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/EditorSessionState.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/EditorSessionStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct EditorSessionStateTests {
    private let sampleRange = NSRange(location: 0, length: 5)

    @Test func editingIsEditable() {
        #expect(EditorSessionState.editing.isTextEditable == true)
    }

    @Test func generatingIsNotEditable() {
        #expect(EditorSessionState.generating(range: sampleRange).isTextEditable == false)
    }

    @Test func reviewingIsNotEditable() {
        #expect(EditorSessionState.reviewing(range: sampleRange, proposedText: "x").isTextEditable == false)
    }

    @Test func generatingReportsIsGenerating() {
        #expect(EditorSessionState.generating(range: sampleRange).isGenerating == true)
        #expect(EditorSessionState.editing.isGenerating == false)
        #expect(EditorSessionState.reviewing(range: sampleRange, proposedText: "x").isGenerating == false)
    }

    @Test func canTriggerRegenerateOnlyWhenEditingAndSelectionNonEmpty() {
        #expect(EditorSessionState.canTriggerRegenerate(state: .editing, hasNonEmptySelection: true) == true)
        #expect(EditorSessionState.canTriggerRegenerate(state: .editing, hasNonEmptySelection: false) == false)
        #expect(EditorSessionState.canTriggerRegenerate(state: .generating(range: sampleRange), hasNonEmptySelection: true) == false)
        #expect(EditorSessionState.canTriggerRegenerate(state: .reviewing(range: sampleRange, proposedText: "x"), hasNonEmptySelection: true) == false)
    }

    @Test func canCloseSheetOnlyWhenEditing() {
        #expect(EditorSessionState.canCloseSheet(state: .editing) == true)
        #expect(EditorSessionState.canCloseSheet(state: .generating(range: sampleRange)) == false)
        #expect(EditorSessionState.canCloseSheet(state: .reviewing(range: sampleRange, proposedText: "x")) == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: FAIL to compile with "cannot find type 'EditorSessionState' in scope" (the type doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// The unified editor's session state: freely editing the full text, running a
/// fragment regeneration, or reviewing its result before accept/reject. Only
/// one fragment operation is ever in flight at a time — there is no queueing.
enum EditorSessionState: Equatable {
    case editing
    case generating(range: NSRange)
    case reviewing(range: NSRange, proposedText: String)

    /// The text view must be read-only in every state except `.editing`, so a
    /// user can't edit around a fragment that's mid-flight or awaiting a
    /// decision.
    var isTextEditable: Bool {
        self == .editing
    }

    var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }

    /// A fragment regeneration can only be triggered while idle, over a
    /// non-empty selection.
    static func canTriggerRegenerate(state: EditorSessionState, hasNonEmptySelection: Bool) -> Bool {
        state == .editing && hasNonEmptySelection
    }

    /// Сохранить/Отмена must wait until any in-flight fragment operation is
    /// resolved (accepted or rejected), so the user can't lose track of a
    /// pending decision.
    static func canCloseSheet(state: EditorSessionState) -> Bool {
        state == .editing
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`. Then run the new tests via Cmd+U in Xcode (or `xcodebuild test`, accepting it may hang on the UI-test target per this project's known CLI issue — kill it and rely on Cmd+U) and confirm all `EditorSessionStateTests` pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/EditorSessionState.swift SEOContentCreator/SEOContentCreatorTests/EditorSessionStateTests.swift
git commit -m "Add EditorSessionState for the unified editor"
```

---

## Task 2: Simplify `FragmentEditor` — drop splice/version-creation responsibilities

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/FragmentEditor.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift:113-179` (the `FragmentEditorTests` struct)

**Context:** Today `FragmentEditor.run(fullText:fragment:...)` finds the fragment in `fullText` via `FragmentSplicer` (text search) and stores the whole spliced document in `proposedText`; `accept(topic:in:)` then creates an `ArticleVersion`. The new unified editor already knows the fragment's exact `NSRange` in its own text, so `FragmentEditor` only needs to run the AI call and hand back the rewritten fragment text — no splicing, no version creation.

- [ ] **Step 1: Write the failing test (replaces the old `accept`/`ambiguous` tests)**

Replace the `@MainActor struct FragmentEditorTests { ... }` block in `SEOContentCreatorTests/FragmentEditTests.swift` (currently lines ~113-179) with:

```swift
@MainActor
struct FragmentEditorTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Topic.self, PromptRecommendation.self, ArticleVersion.self, GenerationJob.self, PersistedRemark.self,
            AIRole.self, ContextBlock.self, SkillPreset.self, SemanticKeyword.self, PublishedSitePage.self,
            configurations: config
        )
    }

    private func tokenStream(_ text: String) -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.token(text))
                continuation.yield(.finish(reason: "stop"))
                continuation.finish()
            }
        }
    }

    private func errorStream() -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "test", code: 1))
            }
        }
    }

    @Test func successProducesRewrittenFragment() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        context.insert(topic)

        let editor = FragmentEditor(streamProvider: tokenStream("  Новый кусок.  "), keyProvider: { "key" })
        await editor.run(
            fragment: "Старый кусок.",
            instruction: "Упрости.",
            roleKey: "editor",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 4000,
            source: .skillApplied,
            topic: topic,
            in: context
        )

        // Trimmed — leading/trailing whitespace from the model's raw output is stripped.
        #expect(editor.rewrittenFragment == "Новый кусок.")
        #expect(editor.lastErrorMessage == nil)

        let jobs = try context.fetch(FetchDescriptor<GenerationJob>())
        #expect(jobs.count == 1)
        #expect(jobs.first?.status == .success)
    }

    @Test func errorPathSurfacesMessageAndNoRewrittenFragment() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        context.insert(topic)

        let editor = FragmentEditor(streamProvider: errorStream(), keyProvider: { "key" })
        await editor.run(
            fragment: "Кусок.",
            instruction: "Упрости.",
            roleKey: "author",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 4000,
            source: .fragmentRegenerated,
            topic: topic,
            in: context
        )

        #expect(editor.rewrittenFragment == nil)
        #expect(editor.lastErrorMessage != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: FAIL to compile — `FragmentEditor.run` doesn't have this signature yet, and `rewrittenFragment` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Replace the whole contents of `SEOContentCreator/SEOContentCreator/Logic/FragmentEditor.swift` with:

```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class FragmentEditor {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = () throws -> String

    var streamingText: String = ""
    var isRunning: Bool = false
    var lastErrorMessage: String?
    var lastWarningMessage: String?
    /// The AI's rewritten fragment (trimmed), nil until a successful run finishes.
    /// The caller (the unified editor) already knows the exact range this
    /// fragment came from, so splicing it back into the full text and
    /// deciding whether/when to persist a new `ArticleVersion` is entirely
    /// the caller's responsibility.
    var rewrittenFragment: String?

    private(set) var agentName: String?

    private let streamProvider: StreamProvider
    private let keyProvider: KeyProvider

    init(streamProvider: @escaping StreamProvider, keyProvider: @escaping KeyProvider) {
        self.streamProvider = streamProvider
        self.keyProvider = keyProvider
    }

    static func live() -> FragmentEditor {
        FragmentEditor(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens, reasoningEffort in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey, system: system, user: user,
                    model: model, temperature: temperature, maxTokens: maxTokens,
                    reasoningEffort: reasoningEffort
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() }
        )
    }

    func run(
        fragment: String,
        instruction: String,
        roleKey: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        source: VersionSource,
        topic: Topic,
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastWarningMessage = nil
        rewrittenFragment = nil

        let role = fetchRole(roleKey, in: context)
        let name = role?.name ?? "ИИ"
        agentName = name
        let job = GenerationJob(stageLabel: source.rawValue, agentName: name, modelName: model)
        job.topic = topic
        context.insert(job)

        do {
            let key = try keyProvider()
            let roleContext = buildRoleContext(role, in: context)
            let prompt = FragmentPromptBuilder().build(
                roleContext: roleContext, instruction: instruction, fragment: fragment
            )
            var collected = ""
            var truncated = false
            var lastFlush = ContinuousClock.now
            for try await event in streamProvider(
                key, prompt.system, prompt.user, model, temperature, maxTokens, nil
            ) {
                switch event {
                case .token(let t):
                    collected += t
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(100) {
                        streamingText = collected
                        lastFlush = now
                    }
                case .finish(reason: let reason):
                    if reason == "length" { truncated = true }
                case .usage(let promptTokens, let completionTokens):
                    job.promptTokens = promptTokens
                    job.completionTokens = completionTokens
                }
            }
            streamingText = collected // final flush after throttling
            if truncated {
                lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
            }

            rewrittenFragment = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            job.status = .success
            job.finishedAt = .now
        } catch {
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            job.errorMessage = message
            job.status = .error
            job.finishedAt = .now
            lastErrorMessage = message
        }

        isRunning = false
    }

    private func fetchRole(_ key: String, in context: ModelContext) -> AIRole? {
        let descriptor = FetchDescriptor<AIRole>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor))?.first
    }

    private func buildRoleContext(_ role: AIRole?, in context: ModelContext) -> String {
        guard let role else { return "" }
        let blocks = (try? context.fetch(FetchDescriptor<ContextBlock>())) ?? []
        return RoleContextAssembler.assemble(role: role, blocks: blocks)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`. This will still fail until Task 3 removes the now-incompatible `FragmentSplicerTests` and Task 6 removes `FragmentEditSheet.swift` (the only other caller of the old `FragmentEditor` API) — see the note at the end of this task.
Then confirm `FragmentEditorTests` passes via Cmd+U once the whole plan's compile errors are resolved (Task 6).

**Note:** `FragmentEditSheet.swift` still calls the old `FragmentEditor.run(fullText:fragment:...)`/`.accept(...)`/`.proposedText` API and will fail to compile after this step. That's expected — Task 6 deletes `FragmentEditSheet.swift` entirely. Don't try to patch it up in this task; the project won't build cleanly again until Task 6 lands. If you need an intermediate green build, cherry-pick Task 6's deletions early.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/FragmentEditor.swift SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift
git commit -m "Simplify FragmentEditor: return rewritten fragment only, no splice/version creation"
```

---

## Task 3: Delete `FragmentSplicer` and its tests

**Files:**
- Delete: `SEOContentCreator/SEOContentCreator/Logic/FragmentSplicer.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift` (remove the `FragmentSplicerTests` struct)

**Context:** The fragment is now always a real text-view selection with a known exact range (see design doc's "Key simplification"), so the substring-search splice and its not-found/ambiguous error cases no longer apply anywhere.

- [ ] **Step 1: Remove the `FragmentSplicerTests` struct**

Delete this whole struct from `SEOContentCreatorTests/FragmentEditTests.swift` (it currently sits between `VersionSourceFragmentTests`/`SkillPresetDefaultsTests` and `FragmentPromptBuilderTests`):

```swift
struct FragmentSplicerTests {
    @Test func replacesUniqueFragment() { ... }
    @Test func notFoundWhenMissing() { ... }
    @Test func notFoundWhenFragmentEmpty() { ... }
    @Test func ambiguousWhenMultipleMatches() { ... }
    @Test func whitespaceSensitiveMatch() { ... }
}
```

- [ ] **Step 2: Delete the source file**

```bash
rm SEOContentCreator/SEOContentCreator/Logic/FragmentSplicer.swift
```

- [ ] **Step 3: Verify nothing else references it**

Run: `grep -rn "FragmentSplicer" SEOContentCreator/`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add -u SEOContentCreator/SEOContentCreator/Logic/FragmentSplicer.swift SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift
git commit -m "Delete FragmentSplicer: fragment location is now an exact NSRange, not a text search"
```

---

## Task 4: Extend `MarkdownTextEditor` — selection reporting, lockable, highlightable

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/MarkdownTextEditor.swift`

**Context:** No automated tests for this file today (its existing keyboard-shortcut logic is untested AppKit glue) — this task is verified by building and by the manual QA checklist in Task 8, consistent with the existing project convention for this file.

- [ ] **Step 1: Replace the whole file**

```swift
import SwiftUI
import AppKit

/// A plain-text NSTextView wrapper for editing Markdown, with Google-Docs-style
/// keyboard shortcuts that insert/toggle Markdown syntax around the selection
/// or current line. The stored text stays a plain Markdown string — there is
/// no rich-text/AttributedString conversion. Background highlighting (see
/// `highlightRange`) uses `NSLayoutManager` temporary attributes, which are
/// display-only and never touch the stored string.
///
/// Shortcuts: Cmd+B bold (`**..**`), Cmd+I italic (`_.._`),
/// Cmd+Option+1/2/3 heading level 1/2/3 (`#`/`##`/`###` on the current line).
/// Cmd+1..3 are intentionally avoided — macOS reserves them for window tab
/// switching, which would swallow the key event before the text view sees it.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 14)
    /// Set to `false` to make the editor temporarily read-only, e.g. while a
    /// fragment regeneration is in flight or awaiting accept/reject.
    var isEditable: Bool = true
    /// Called whenever the text view's selection changes. `range.length == 0`
    /// means an empty (caret-only) selection; `rect` is the selection's
    /// bounding box in the enclosing `NSScrollView`'s coordinate space (nil
    /// when the selection is empty), for positioning a SwiftUI overlay button.
    var onSelectionChange: (NSRange, CGRect?) -> Void = { _, _ in }
    /// When non-nil, this range gets a temporary highlighted background — used
    /// to mark a freshly regenerated fragment awaiting accept/reject.
    var highlightRange: NSRange?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownEditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = font
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.font != font {
            textView.font = font
        }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        applyHighlight(to: textView)
    }

    private func applyHighlight(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        guard let highlightRange,
              highlightRange.location >= 0,
              highlightRange.location + highlightRange.length <= fullRange.length
        else { return }
        layoutManager.addTemporaryAttribute(
            .backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.25),
            forCharacterRange: highlightRange
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSelectionChange: (NSRange, CGRect?) -> Void

        init(text: Binding<String>, onSelectionChange: @escaping (NSRange, CGRect?) -> Void) {
            self.text = text
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            guard range.length > 0,
                  let layoutManager = tv.layoutManager,
                  let container = tv.textContainer,
                  let scrollView = tv.enclosingScrollView
            else {
                onSelectionChange(range, nil)
                return
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += tv.textContainerInset.width
            rect.origin.y += tv.textContainerInset.height
            let rectInScrollView = tv.convert(rect, to: scrollView)
            onSelectionChange(range, rectInScrollView)
        }
    }
}

/// Handles the Markdown keyboard shortcuts directly at the AppKit level, so
/// they work regardless of SwiftUI focus/selection-binding plumbing.
final class MarkdownEditorTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers {
            if event.modifierFlags.contains(.option) {
                switch chars {
                case "1": setHeading(level: 1); return
                case "2": setHeading(level: 2); return
                case "3": setHeading(level: 3); return
                default: break
                }
            } else {
                switch chars {
                case "b": wrapSelection(prefix: "**", suffix: "**"); return
                case "i": wrapSelection(prefix: "_", suffix: "_"); return
                default: break
                }
            }
        }
        super.keyDown(with: event)
    }

    /// Wraps the current selection in `prefix`/`suffix`. With no selection,
    /// inserts an empty pair and places the cursor between them.
    private func wrapSelection(prefix: String, suffix: String) {
        let range = selectedRange()
        let ns = string as NSString
        let selected = ns.substring(with: range)
        let replacement = prefix + selected + suffix
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
        let cursor = selected.isEmpty
            ? range.location + (prefix as NSString).length
            : range.location + (replacement as NSString).length
        setSelectedRange(NSRange(location: cursor, length: 0))
    }

    /// Replaces the leading `#`s (if any) on the current line with `level` of them.
    private func setHeading(level: Int) {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        var line = ns.substring(with: lineRange)
        let hadTrailingNewline = line.hasSuffix("\n")
        if hadTrailingNewline { line.removeLast() }

        var body = Substring(line)
        while body.first == "#" { body = body.dropFirst() }
        if body.first == " " { body = body.dropFirst() }

        let newLine = String(repeating: "#", count: level) + " " + body + (hadTrailingNewline ? "\n" : "")
        guard shouldChangeText(in: lineRange, replacementString: newLine) else { return }
        replaceCharacters(in: lineRange, with: newLine)
        didChangeText()
        setSelectedRange(NSRange(location: lineRange.location + (newLine as NSString).length, length: 0))
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: still fails overall (Task 6 hasn't landed yet, `FragmentEditSheet.swift`/`ManualEditSheet.swift` still reference the old API), but confirm there are **no errors mentioning `MarkdownTextEditor.swift`** in the output — only errors from `FragmentEditSheet.swift`/`ManualEditSheet.swift` are expected at this point.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/MarkdownTextEditor.swift
git commit -m "Extend MarkdownTextEditor: selection reporting, lockable, range highlight"
```

---

## Task 5: Create `EditorSheet.swift` — the unified editor view

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/EditorSheet.swift`

**Context:** This is the main new screen. No automated tests (SwiftUI view rendering + AppKit coordinate math aren't practically unit-testable in this codebase — same convention as `ManualEditSheet`/`FragmentEditSheet`/`StageBarView` today, none of which have tests); the state-machine decisions it relies on (`EditorSessionState`) are already tested in Task 1. Verified by build + the manual QA checklist in Task 8.

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import SwiftData

private enum FragmentMode: String, CaseIterable, Identifiable {
    case skill
    case comment
    var id: String { rawValue }
    var title: String { self == .skill ? "Скилл" : "Свой комментарий" }
}

struct EditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @Query(sort: \SkillPreset.order) private var skills: [SkillPreset]

    @State private var text = ""
    @State private var sessionState: EditorSessionState = .editing
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var selectionRect: CGRect?
    @State private var pendingOriginalFragment = ""

    @State private var showRegenerateCard = false
    @State private var fragmentMode: FragmentMode = .skill
    @State private var fragmentComment = ""
    @State private var selectedSkillID: UUID?
    @State private var editor = FragmentEditor.live()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Редактор").font(.headline)
                Spacer()
                if sessionState.isGenerating {
                    ProgressView().controlSize(.small)
                }
            }
            Text("Правка сохранится как новая версия и станет текущей, когда нажмёте «Сохранить». Выделите фрагмент и нажмите «Переписать», чтобы перегенерировать его через ИИ. Cmd+B — жирный, Cmd+I — курсив, Cmd+Option+1/2/3 — заголовок.")
                .font(.caption).foregroundStyle(.secondary)

            if let error = editor.lastErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                    Text(error).font(.callout)
                    Spacer()
                    Button("Скрыть") { editor.lastErrorMessage = nil }
                }
                .padding(8)
                .background(Color.red.opacity(0.12))
            }
            if let warning = editor.lastWarningMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(warning).font(.callout)
                    Spacer()
                    Button("Скрыть") { editor.lastWarningMessage = nil }
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
            }

            editorArea

            if case .reviewing = sessionState {
                HStack {
                    Spacer()
                    Button("Отклонить", role: .destructive, action: rejectFragment)
                    Button("Принять", action: acceptFragment).keyboardShortcut(.defaultAction)
                }
            }

            HStack {
                Button("Отмена") { dismiss() }
                    .disabled(!canCloseSheet)
                Spacer()
                Button("Перегенерировать выделенное") { showRegenerateCard = true }
                    .disabled(!canTriggerRegenerate)
                Button("Сохранить", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
        }
        .padding()
        .frame(minWidth: 720, idealWidth: 900, maxWidth: .infinity,
               minHeight: 560, idealHeight: 700, maxHeight: .infinity)
        .onAppear { text = topic.currentVersion?.text ?? "" }
    }

    // MARK: Editor area (text view + floating "Переписать" button + regenerate card)

    @ViewBuilder private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            MarkdownTextEditor(
                text: $text,
                font: .systemFont(ofSize: 15),
                isEditable: sessionState.isTextEditable,
                onSelectionChange: { range, rect in
                    selectedRange = range
                    selectionRect = rect
                },
                highlightRange: highlightRange
            )
            .frame(minWidth: 500, minHeight: 300)
            .border(Color.secondary.opacity(0.3))

            if canTriggerRegenerate, let rect = selectionRect {
                Button {
                    showRegenerateCard = true
                } label: {
                    Label("Переписать", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .offset(x: rect.minX, y: max(0, rect.minY - 30))
            }

            if showRegenerateCard, let rect = selectionRect {
                regenerateCard
                    .offset(x: rect.minX, y: rect.maxY + 6)
            }
        }
    }

    @ViewBuilder private var regenerateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Переписать выделенный фрагмент").font(.headline)

            Picker("Режим", selection: $fragmentMode) {
                ForEach(FragmentMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if fragmentMode == .skill {
                Text("Скилл").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(skills) { skill in
                            HStack {
                                Text(skill.name)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selectedSkillID == skill.uuid ? Color.accentColor.opacity(0.2) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedSkillID = skill.uuid }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 140)
                .border(Color.secondary.opacity(0.3))
            } else {
                Text("Что не нравится").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $fragmentComment)
                    .frame(minHeight: 70)
                    .border(Color.secondary.opacity(0.3))
            }

            HStack {
                Button("Отмена") { showRegenerateCard = false }
                Spacer()
                Button("Перегенерировать", action: startRegenerate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStartRegenerate)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    // MARK: Derived state

    private var canTriggerRegenerate: Bool {
        EditorSessionState.canTriggerRegenerate(state: sessionState, hasNonEmptySelection: selectedRange.length > 0)
    }

    private var canCloseSheet: Bool {
        EditorSessionState.canCloseSheet(state: sessionState)
    }

    private var canStartRegenerate: Bool {
        switch fragmentMode {
        case .skill:   return selectedSkillID != nil
        case .comment: return !fragmentComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var highlightRange: NSRange? {
        if case .reviewing(let range, _) = sessionState { return range }
        return nil
    }

    private var hasChanges: Bool {
        guard sessionState == .editing else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && text != (topic.currentVersion?.text ?? "")
    }

    // MARK: Actions

    private func startRegenerate() {
        let ns = text as NSString
        guard selectedRange.length > 0, selectedRange.location + selectedRange.length <= ns.length else { return }
        let fragment = ns.substring(with: selectedRange)

        let instruction: String
        let source: VersionSource
        let roleKey: String
        switch fragmentMode {
        case .skill:
            guard let skill = skills.first(where: { $0.uuid == selectedSkillID }) else { return }
            instruction = skill.prompt
            source = .skillApplied
            roleKey = skill.roleKey
        case .comment:
            instruction = "Перепиши фрагмент с учётом замечания: \(fragmentComment)"
            source = .fragmentRegenerated
            roleKey = "author"
        }

        pendingOriginalFragment = fragment
        let range = selectedRange
        sessionState = .generating(range: range)
        showRegenerateCard = false

        Task {
            await editor.run(
                fragment: fragment, instruction: instruction, roleKey: roleKey,
                model: model, temperature: 0.6, maxTokens: 4000, source: source,
                topic: topic, in: context
            )
            guard let rewritten = editor.rewrittenFragment else {
                sessionState = .editing
                return
            }
            let updated = (text as NSString).replacingCharacters(in: range, with: rewritten)
            text = updated
            let newRange = NSRange(location: range.location, length: (rewritten as NSString).length)
            sessionState = .reviewing(range: newRange, proposedText: rewritten)
        }
    }

    private func acceptFragment() {
        guard case .reviewing = sessionState else { return }
        sessionState = .editing
    }

    private func rejectFragment() {
        guard case .reviewing(let range, _) = sessionState else { return }
        text = (text as NSString).replacingCharacters(in: range, with: pendingOriginalFragment)
        sessionState = .editing
    }

    private func save() {
        VersionActions.applyManualEdit(topic: topic, newText: text, in: context)
        dismiss()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: no errors mentioning `EditorSheet.swift`. `FragmentEditSheet.swift`/`ManualEditSheet.swift` and `TopicWorkspaceView.swift` will still show errors/staleness until Task 6.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/EditorSheet.swift
git commit -m "Add EditorSheet: unified manual edit + fragment regeneration screen"
```

---

## Task 6: Wire `EditorSheet` into `TopicWorkspaceView`; delete the two old sheets

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift:24-25` (state), `:138-139` (sheets), `:247-251` (toolbar)
- Delete: `SEOContentCreator/SEOContentCreator/Views/ManualEditSheet.swift`
- Delete: `SEOContentCreator/SEOContentCreator/Views/FragmentEditSheet.swift`

- [ ] **Step 1: Replace the two `@State` flags**

In `TopicWorkspaceView.swift`, replace:

```swift
    @State private var showFragmentEdit = false
    @State private var showManualEdit = false
```

with:

```swift
    @State private var showEditor = false
```

- [ ] **Step 2: Replace the two `.sheet` modifiers**

Replace:

```swift
        .sheet(isPresented: $showFragmentEdit) { FragmentEditSheet(topic: topic) }
        .sheet(isPresented: $showManualEdit) { ManualEditSheet(topic: topic) }
```

with:

```swift
        .sheet(isPresented: $showEditor) { EditorSheet(topic: topic) }
```

- [ ] **Step 3: Replace the two toolbar buttons**

Replace:

```swift
        ToolbarItem { Button { showFragmentEdit = true } label: { Label("Правка фрагмента", systemImage: "wand.and.stars") } }
        ToolbarItem {
            Button { showManualEdit = true } label: { Label("Ручная правка", systemImage: "pencil") }
                .disabled(topic.currentVersion == nil)
        }
```

with:

```swift
        ToolbarItem {
            Button { showEditor = true } label: { Label("Редактор", systemImage: "pencil") }
                .disabled(topic.currentVersion == nil)
        }
```

- [ ] **Step 4: Delete the two old sheet files**

```bash
rm SEOContentCreator/SEOContentCreator/Views/ManualEditSheet.swift
rm SEOContentCreator/SEOContentCreator/Views/FragmentEditSheet.swift
```

- [ ] **Step 5: Verify the whole project builds and tests compile**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`, with no remaining references to `ManualEditSheet`, `FragmentEditSheet`, `FragmentSplicer`, `showManualEdit`, or `showFragmentEdit`.

Run: `grep -rn "ManualEditSheet\|FragmentEditSheet\|showManualEdit\|showFragmentEdit" SEOContentCreator/`
Expected: no output.

- [ ] **Step 6: Run the full test suite**

Run via Cmd+U in Xcode (not `xcodebuild test`, which is known to hang on this project's CLI runner — see project memory). Confirm `EditorSessionStateTests`, the updated `FragmentEditorTests`, `FragmentPromptBuilderTests`, `VersionSourceFragmentTests`, `SkillPresetDefaultsTests`, and `SkillPresetSeederTests` all pass (this file's other structs are untouched by this plan and should be unaffected).

- [ ] **Step 7: Commit**

```bash
git add -u SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift SEOContentCreator/SEOContentCreator/Views/ManualEditSheet.swift SEOContentCreator/SEOContentCreator/Views/FragmentEditSheet.swift
git commit -m "Replace Ручная правка + Правка фрагмента with one Редактор screen"
```

---

## Task 7: Manual QA pass

**Files:** none (manual verification only — see design doc's Testing Plan and `ui-review`/`write-tests` project conventions for why this is required alongside the automated tests above).

- [ ] **Step 1: Build and reinstall for manual testing**

```bash
cd SEOContentCreator && xcodebuild build -scheme SEOContentCreator -configuration Release
```
Then quit any running copy, replace `/Applications/SEOContentCreator.app` with the fresh build, and relaunch — same procedure already used for previous features in this project.

- [ ] **Step 2: Walk through the checklist from the design doc**

Open a topic with an existing article version, click "Редактор", and confirm:

1. Selecting a fragment shows the floating "✨ Переписать" button above the selection; the toolbar's "Перегенерировать выделенное" button does the same thing.
2. Regenerate via a skill preset — the fragment updates in place with a highlighted background, and an Принять/Отклонить bar appears.
3. Regenerate via a custom comment — same behavior.
4. Принять a fragment, then select a different fragment and Отклонить it — confirm the rejected one reverts to its original text and the accepted one stays changed.
5. Manually type in another part of the article both before and after doing a fragment regeneration.
6. Click Сохранить — confirm exactly one new `ArticleVersion` appears in "Версии" containing all the manual edits and accepted fragments together; reopen the editor and confirm the saved text is now `topic.currentVersion`.
7. Open the editor again, make a change, click Отмена — confirm no new version was created.
8. Find (or create) an article where the same sentence appears twice, regenerate one occurrence — confirm only the selected occurrence changes (this used to be the "fragment occurs 2 times" failure).
9. Confirm Сохранить/Отмена/the regenerate buttons are disabled while a fragment is generating or awaiting accept/reject.

- [ ] **Step 3: Record the result**

If everything checks out, this should be reflected in `ai/changelog.md` as part of `task-finish`, per this project's workflow — not before, and not as part of this plan's execution.
