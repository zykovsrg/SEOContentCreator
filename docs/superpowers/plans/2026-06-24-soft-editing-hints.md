# Soft Editing Hints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add algorithmic (no-AI) soft editing hints — long sentences, repeated word-roots nearby, and clichés from an editable dictionary — shown read-only in a sheet over a topic's current text.

**Architecture:** A pure, UI-free analyzer (`SoftHints.analyze`) produces `[SoftHint]` with character ranges; a new SwiftData model `EditorDictionary` holds the cliché list + thresholds (edited in «Шаблоны»); a `SoftHintsSheet` renders the text with multi-range highlighting (`MultiHighlightedText`) plus a list panel. Nothing is saved or mutated — purely informational.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`, `@Test`, `#expect`). macOS app. Xcode project uses synchronized folders — new files under `Logic/`, `Models/`, `Views/`, `SEOContentCreatorTests/` are auto-included (no `project.pbxproj` edits).

**Build/test reality:** CLI `xcodebuild test` hangs in this environment. Use `xcodebuild build-for-testing` to verify compilation; run tests in Xcode via Cmd+U. Each "run tests" step below means: build-for-testing green, then Cmd+U green.

---

## File Structure

Source root: `SEOContentCreator/SEOContentCreator/`
Test root: `SEOContentCreator/SEOContentCreatorTests/`

New files:
- `Logic/SoftHints.swift` — analyzer types (`SoftHintKind`, `SoftHint`, `SoftHintsSettings`) + `SoftHints` enum with `analyze` and helpers. Pure, no SwiftData/SwiftUI.
- `Models/EditorDictionary.swift` — `@Model` + `EditorDictionaryDefaults` + `settings`/`cliches` computed helpers.
- `Logic/EditorDictionarySeeder.swift` — `seedIfNeeded(in:)`.
- `Views/MultiHighlightedText.swift` — read-only text with multiple colored ranges + one emphasized range.
- `Views/SoftHintsSheet.swift` — sheet: `MultiHighlightedText` + hints panel.
- `SEOContentCreatorTests/SoftHintsTests.swift` — unit tests for the analyzer.

Modified files:
- `SEOContentCreatorApp.swift:10` — add `EditorDictionary.self` to `.modelContainer(for:)`.
- `Views/RootView.swift:22` — add `EditorDictionarySeeder.seedIfNeeded(in: context)`.
- `Views/TopicWorkspaceView.swift` — toolbar button «Подсказки» + `@State showHints` + `.sheet`.
- `Views/TemplatesView.swift` — new selection case + section «Словарь правок» + editor view.

---

## Task 1: Analyzer scaffold + long-sentence detection

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SoftHints.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SoftHintsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SoftHintsTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct SoftHintsTests {
    // MARK: Long sentences

    @Test func flagsSentenceOverLimit() {
        let long = Array(repeating: "слово", count: 12).joined(separator: " ") + "."
        let hints = SoftHints.analyze(
            text: long,
            settings: SoftHintsSettings(longSentenceWordLimit: 10, repeatWindowWords: 30, cliches: [])
        )
        let longOnes = hints.filter { $0.kind == .longSentence }
        #expect(longOnes.count == 1)
    }

    @Test func ignoresSentenceAtOrUnderLimit() {
        let short = Array(repeating: "слово", count: 10).joined(separator: " ") + "."
        let hints = SoftHints.analyze(
            text: short,
            settings: SoftHintsSettings(longSentenceWordLimit: 10, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .longSentence }.isEmpty)
    }

    @Test func splitsOnTerminatorsAndNewlines() {
        // Two long sentences separated by a newline → two hints.
        let one = Array(repeating: "раз", count: 6).joined(separator: " ")
        let text = "\(one).\n\(one)?"
        let hints = SoftHints.analyze(
            text: text,
            settings: SoftHintsSettings(longSentenceWordLimit: 5, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .longSentence }.count == 2)
    }

    @Test func handlesEmptyText() {
        let hints = SoftHints.analyze(text: "", settings: .default)
        #expect(hints.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Build: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: FAIL — `cannot find 'SoftHints' in scope` / `SoftHintsSettings`.

- [ ] **Step 3: Write minimal implementation**

Create `Logic/SoftHints.swift`:

```swift
import Foundation

enum SoftHintKind: String {
    case longSentence
    case repeatedRoot
    case cliche
}

struct SoftHint: Identifiable {
    let id = UUID()
    let kind: SoftHintKind
    let range: Range<String.Index>
    let message: String
}

struct SoftHintsSettings {
    var longSentenceWordLimit: Int
    var repeatWindowWords: Int
    var cliches: [String]

    static let `default` = SoftHintsSettings(
        longSentenceWordLimit: 30, repeatWindowWords: 30, cliches: []
    )
}

enum SoftHints {
    /// Deterministic order: long sentences → repeated roots → clichés.
    static func analyze(text: String, settings: SoftHintsSettings) -> [SoftHint] {
        longSentenceHints(text, limit: settings.longSentenceWordLimit)
    }

    // MARK: Long sentences

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "…", "\n"]

    static func longSentenceHints(_ text: String, limit: Int) -> [SoftHint] {
        sentenceRanges(text).compactMap { range in
            let count = wordRanges(in: text, range: range).count
            guard count > limit else { return nil }
            return SoftHint(
                kind: .longSentence,
                range: range,
                message: "Длинное предложение: \(count) слов. Стоит разбить."
            )
        }
    }

    /// Sentence ranges, split on `.!?…` and newlines, each trimmed of surrounding whitespace.
    static func sentenceRanges(_ text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            if sentenceTerminators.contains(text[i]) {
                let end = text.index(after: i)
                if let r = trimmedRange(text, start..<end) { result.append(r) }
                start = end
            }
            i = text.index(after: i)
        }
        if start < text.endIndex, let r = trimmedRange(text, start..<text.endIndex) {
            result.append(r)
        }
        return result
    }

    /// Word ranges (maximal runs of letters/digits) inside `range`.
    static func wordRanges(in text: String, range: Range<String.Index>) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var wordStart: String.Index?
        var i = range.lowerBound
        while i < range.upperBound {
            let c = text[i]
            if c.isLetter || c.isNumber {
                if wordStart == nil { wordStart = i }
            } else if let s = wordStart {
                result.append(s..<i); wordStart = nil
            }
            i = text.index(after: i)
        }
        if let s = wordStart { result.append(s..<range.upperBound) }
        return result
    }

    /// Trims leading/trailing whitespace & newlines; nil if the result is empty.
    private static func trimmedRange(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace || text[lower].isNewline {
            lower = text.index(after: lower)
        }
        while lower < upper {
            let before = text.index(before: upper)
            if text[before].isWhitespace || text[before].isNewline { upper = before } else { break }
        }
        return lower < upper ? lower..<upper : nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Build: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5` → BUILD SUCCEEDED.
Then run in Xcode (Cmd+U): the 4 `SoftHintsTests` long-sentence/empty tests PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SoftHints.swift SEOContentCreator/SEOContentCreatorTests/SoftHintsTests.swift
git commit -m "feat(hints): SoftHints analyzer + long-sentence detection"
```

---

## Task 2: Repeated-root detection

**Files:**
- Modify: `Logic/SoftHints.swift`
- Test: `SEOContentCreatorTests/SoftHintsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `SoftHintsTests` struct:

```swift
    // MARK: Repeated roots

    @Test func flagsRepeatedRootWithinWindow() {
        let hints = SoftHints.analyze(
            text: "Обработка данных требует обработать поток.",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .repeatedRoot }.count == 1)
    }

    @Test func ignoresRepeatedRootOutsideWindow() {
        // Filler words are <5 letters: skipped for root-matching, but they still
        // occupy word positions, so they push the two "обраб…" words apart.
        let filler = Array(repeating: "да", count: 10).joined(separator: " ")
        let text = "обработка \(filler) обработать"
        let hints = SoftHints.analyze(
            text: text,
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 3, cliches: [])
        )
        #expect(hints.filter { $0.kind == .repeatedRoot }.isEmpty)
    }

    @Test func flagsExactWordRepeat() {
        let hints = SoftHints.analyze(
            text: "качество и ещё раз качество важно",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .repeatedRoot }.count == 1)
    }

    @Test func ignoresShortWordsForRoots() {
        // "и", "на", "это" are <5 letters → no root repeats even if duplicated nearby.
        let hints = SoftHints.analyze(
            text: "это и это и это",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .repeatedRoot }.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Build, then Cmd+U: the 4 new repeated-root tests FAIL (analyze returns no `.repeatedRoot` hints yet).

- [ ] **Step 3: Write minimal implementation**

In `Logic/SoftHints.swift`, change `analyze` to append repeated-root hints:

```swift
    static func analyze(text: String, settings: SoftHintsSettings) -> [SoftHint] {
        longSentenceHints(text, limit: settings.longSentenceWordLimit)
        + repeatedRootHints(text, window: settings.repeatWindowWords)
    }
```

Add below the long-sentence section:

```swift
    // MARK: Repeated roots

    private static let minRootWordLength = 5
    private static let rootPrefixLength = 5

    static func repeatedRootHints(_ text: String, window: Int) -> [SoftHint] {
        let allWords = wordRanges(in: text, range: text.startIndex..<text.endIndex)
        var lastIndex: [String: Int] = [:]
        var lastRange: [String: Range<String.Index>] = [:]
        var hints: [SoftHint] = []
        for (i, r) in allWords.enumerated() {
            let raw = String(text[r])
            let norm = normalized(raw)
            guard norm.count >= minRootWordLength else { continue }
            let root = String(norm.prefix(rootPrefixLength))
            if let j = lastIndex[root], i - j <= window {
                let prev = lastRange[root].map { String(text[$0]) } ?? ""
                hints.append(SoftHint(
                    kind: .repeatedRoot,
                    range: r,
                    message: "Повтор однокоренного рядом: «\(raw)» и «\(prev)»."
                ))
            }
            lastIndex[root] = i
            lastRange[root] = r
        }
        return hints
    }

    /// Lowercase + ё→е so that "Ёлка"/"елка" share a root.
    static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Build green, Cmd+U: all repeated-root tests PASS (and Task 1 tests still PASS).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SoftHints.swift SEOContentCreator/SEOContentCreatorTests/SoftHintsTests.swift
git commit -m "feat(hints): repeated-root detection (prefix-based)"
```

---

## Task 3: Cliché detection

**Files:**
- Modify: `Logic/SoftHints.swift`
- Test: `SEOContentCreatorTests/SoftHintsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `SoftHintsTests`:

```swift
    // MARK: Clichés

    @Test func findsClicheCaseAndYoInsensitive() {
        let hints = SoftHints.analyze(
            text: "В Наше Время всё иначе.",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30,
                                        cliches: ["в наше время"])
        )
        #expect(hints.filter { $0.kind == .cliche }.count == 1)
    }

    @Test func findsMultipleClicheOccurrences() {
        let hints = SoftHints.analyze(
            text: "так или иначе, так или иначе снова",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30,
                                        cliches: ["так или иначе"])
        )
        #expect(hints.filter { $0.kind == .cliche }.count == 2)
    }

    @Test func ignoresClicheInsideLongerWord() {
        // "акт" must not match inside "контакт".
        let hints = SoftHints.analyze(
            text: "наш контакт здесь",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30,
                                        cliches: ["акт"])
        )
        #expect(hints.filter { $0.kind == .cliche }.isEmpty)
    }

    @Test func ignoresEmptyDictionaryEntries() {
        let hints = SoftHints.analyze(
            text: "обычный текст",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30,
                                        cliches: ["", "   "])
        )
        #expect(hints.filter { $0.kind == .cliche }.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Build, Cmd+U: the 4 cliché tests FAIL.

- [ ] **Step 3: Write minimal implementation**

In `analyze`, append clichés:

```swift
    static func analyze(text: String, settings: SoftHintsSettings) -> [SoftHint] {
        longSentenceHints(text, limit: settings.longSentenceWordLimit)
        + repeatedRootHints(text, window: settings.repeatWindowWords)
        + clicheHints(text, cliches: settings.cliches)
    }
```

Add a clichés section:

```swift
    // MARK: Clichés

    static func clicheHints(_ text: String, cliches: [String]) -> [SoftHint] {
        var hints: [SoftHint] = []
        for entry in cliches {
            let phrase = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let found = text.range(
                      of: phrase,
                      options: [.caseInsensitive, .diacriticInsensitive],
                      range: searchStart..<text.endIndex
                  ) {
                if isWordBoundaryMatch(text, found) {
                    hints.append(SoftHint(
                        kind: .cliche,
                        range: found,
                        message: "Штамп: «\(phrase)». Лучше переформулировать."
                    ))
                }
                searchStart = found.upperBound
            }
        }
        return hints
    }

    /// True when the match is not glued to a letter/digit on either side.
    private static func isWordBoundaryMatch(_ text: String, _ range: Range<String.Index>) -> Bool {
        let beforeOK: Bool
        if range.lowerBound == text.startIndex {
            beforeOK = true
        } else {
            let b = text[text.index(before: range.lowerBound)]
            beforeOK = !(b.isLetter || b.isNumber)
        }
        let afterOK: Bool
        if range.upperBound == text.endIndex {
            afterOK = true
        } else {
            let a = text[range.upperBound]
            afterOK = !(a.isLetter || a.isNumber)
        }
        return beforeOK && afterOK
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Build green, Cmd+U: all cliché tests PASS; Tasks 1–2 still PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SoftHints.swift SEOContentCreator/SEOContentCreatorTests/SoftHintsTests.swift
git commit -m "feat(hints): cliché dictionary detection (word-boundary, case/ё-insensitive)"
```

---

## Task 4: EditorDictionary model + defaults + seeder

**Files:**
- Create: `Models/EditorDictionary.swift`
- Create: `Logic/EditorDictionarySeeder.swift`
- Test: `SEOContentCreatorTests/SoftHintsTests.swift` (settings-mapping test)

- [ ] **Step 1: Write the failing test**

Append to `SoftHintsTests`:

```swift
    // MARK: EditorDictionary mapping

    @Test func dictionaryParsesClichesAndBuildsSettings() {
        let dict = EditorDictionary(
            clichesText: "в наше время\n\n  так или иначе  \n",
            longSentenceWordLimit: 25,
            repeatWindowWords: 15
        )
        #expect(dict.cliches == ["в наше время", "так или иначе"])
        let s = dict.settings
        #expect(s.longSentenceWordLimit == 25)
        #expect(s.repeatWindowWords == 15)
        #expect(s.cliches.count == 2)
    }

    @Test func defaultsAreNonEmpty() {
        #expect(EditorDictionaryDefaults.longSentenceWordLimit > 0)
        #expect(EditorDictionaryDefaults.repeatWindowWords > 0)
        #expect(!EditorDictionaryDefaults.clichesText.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Build: FAIL — `cannot find 'EditorDictionary'` / `EditorDictionaryDefaults`.

- [ ] **Step 3: Write minimal implementation**

Create `Models/EditorDictionary.swift`:

```swift
import Foundation
import SwiftData

@Model
final class EditorDictionary {
    var uuid: UUID
    /// Cliché phrases, one per line.
    var clichesText: String
    var longSentenceWordLimit: Int
    var repeatWindowWords: Int
    var version: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        clichesText: String,
        longSentenceWordLimit: Int,
        repeatWindowWords: Int,
        version: Int = 1
    ) {
        self.uuid = UUID()
        self.clichesText = clichesText
        self.longSentenceWordLimit = longSentenceWordLimit
        self.repeatWindowWords = repeatWindowWords
        self.version = version
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension EditorDictionary {
    /// Non-empty, trimmed cliché lines.
    var cliches: [String] {
        clichesText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var settings: SoftHintsSettings {
        SoftHintsSettings(
            longSentenceWordLimit: longSentenceWordLimit,
            repeatWindowWords: repeatWindowWords,
            cliches: cliches
        )
    }
}

enum EditorDictionaryDefaults {
    static let longSentenceWordLimit = 30
    static let repeatWindowWords = 30

    /// Starter cliché list — editable by the user in «Шаблоны».
    static let clichesText = """
    на сегодняшний день
    в наше время
    не секрет, что
    игра стоит свеч
    как известно
    в современном мире
    широкий спектр
    в данной статье
    стоит отметить, что
    """

    static func make() -> EditorDictionary {
        EditorDictionary(
            clichesText: clichesText,
            longSentenceWordLimit: longSentenceWordLimit,
            repeatWindowWords: repeatWindowWords
        )
    }
}
```

Create `Logic/EditorDictionarySeeder.swift`:

```swift
import Foundation
import SwiftData

enum EditorDictionarySeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<EditorDictionary>())) ?? []
        guard existing.isEmpty else { return }
        context.insert(EditorDictionaryDefaults.make())
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Build green, Cmd+U: the two new mapping/defaults tests PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/EditorDictionary.swift SEOContentCreator/SEOContentCreator/Logic/EditorDictionarySeeder.swift SEOContentCreator/SEOContentCreatorTests/SoftHintsTests.swift
git commit -m "feat(hints): EditorDictionary model, defaults, seeder"
```

---

## Task 5: Register model in schema + seed at startup

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift:10`
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift:22`

- [ ] **Step 1: Add the model to the container**

In `SEOContentCreatorApp.swift`, extend the schema array. Replace:

```swift
        .modelContainer(for: [
            Topic.self, KnowledgeNode.self,
            ArticleVersion.self, GenerationJob.self, StageTemplate.self,
            ContextBlock.self, AIRole.self,
            GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
            ExternalDocument.self
        ])
```

with:

```swift
        .modelContainer(for: [
            Topic.self, KnowledgeNode.self,
            ArticleVersion.self, GenerationJob.self, StageTemplate.self,
            ContextBlock.self, AIRole.self,
            GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
            ExternalDocument.self, EditorDictionary.self
        ])
```

- [ ] **Step 2: Seed at startup**

In `RootView.swift`, replace the `.task` block:

```swift
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
        }
```

with:

```swift
        .task {
            StageTemplateSeeder.seedIfNeeded(in: context)
            EditorDictionarySeeder.seedIfNeeded(in: context)
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift SEOContentCreator/SEOContentCreator/Views/RootView.swift
git commit -m "feat(hints): register EditorDictionary in schema + seed at startup"
```

---

## Task 6: MultiHighlightedText view

**Files:**
- Create: `Views/MultiHighlightedText.swift`

No unit test (SwiftUI view); verified by compile + manual check in Task 7/8.

- [ ] **Step 1: Implement the view**

Create `Views/MultiHighlightedText.swift`:

```swift
import SwiftUI

/// Read-only text that paints several colored background ranges, with one
/// optional emphasized range drawn stronger. Ranges are `String.Index` ranges
/// into the SAME `text` value passed in.
struct MultiHighlightedText: View {
    struct Mark {
        let range: Range<String.Index>
        let color: Color
    }

    let text: String
    let marks: [Mark]
    var emphasized: Range<String.Index>?

    var body: some View {
        Text(attributed).textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var a = AttributedString(text)
        for mark in marks {
            paint(&a, range: mark.range, color: mark.color, opacity: 0.30)
        }
        if let emphasized {
            paint(&a, range: emphasized, color: .accentColor, opacity: 0.55)
        }
        return a
    }

    /// Maps a `String.Index` range into `text` onto `AttributedString` indices
    /// by character offset (1:1 for plain text) and sets the background color.
    private func paint(_ a: inout AttributedString, range: Range<String.Index>, color: Color, opacity: Double) {
        let lowerOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: range.upperBound)
        guard lowerOffset >= 0, upperOffset <= a.characters.count, lowerOffset < upperOffset else { return }
        let lower = a.index(a.startIndex, offsetByCharacters: lowerOffset)
        let upper = a.index(a.startIndex, offsetByCharacters: upperOffset)
        a[lower..<upper].backgroundColor = color.opacity(opacity)
    }
}

extension SoftHintKind {
    /// Highlight color per hint type.
    var highlightColor: Color {
        switch self {
        case .longSentence: return .yellow
        case .repeatedRoot: return .orange
        case .cliche:       return .pink
        }
    }

    var title: String {
        switch self {
        case .longSentence: return "Длинное предложение"
        case .repeatedRoot: return "Повтор однокоренного"
        case .cliche:       return "Штамп"
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/MultiHighlightedText.swift
git commit -m "feat(hints): MultiHighlightedText with per-kind colors"
```

---

## Task 7: SoftHintsSheet

**Files:**
- Create: `Views/SoftHintsSheet.swift`

- [ ] **Step 1: Implement the sheet**

Create `Views/SoftHintsSheet.swift`:

```swift
import SwiftUI
import SwiftData

struct SoftHintsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let topic: Topic

    @State private var hints: [SoftHint] = []
    @State private var selectedHintID: UUID?

    private var text: String { topic.currentVersion?.text ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if text.isEmpty {
                ContentUnavailableView("Нет текста для проверки", systemImage: "text.alignleft")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        MultiHighlightedText(text: text, marks: marks, emphasized: emphasizedRange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    Divider()
                    panel.frame(width: 320)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear(perform: recompute)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Подсказки").font(.headline)
                Text("Грубые алгоритмические подсказки. Ничего не сохраняется.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Закрыть") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Найдено: \(hints.count)").font(.headline).foregroundStyle(.secondary).padding(8)
            Divider()
            if hints.isEmpty {
                ContentUnavailableView("Подсказок нет", systemImage: "checkmark.seal")
            } else {
                List(hints) { hint in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hint.kind.title).font(.subheadline).bold()
                            .foregroundStyle(hint.kind.highlightColor)
                        Text(hint.message).font(.callout)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedHintID = hint.id }
                    .listRowBackground(selectedHintID == hint.id ? Color.accentColor.opacity(0.12) : Color.clear)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var marks: [MultiHighlightedText.Mark] {
        hints.map { .init(range: $0.range, color: $0.kind.highlightColor) }
    }

    private var emphasizedRange: Range<String.Index>? {
        guard let id = selectedHintID else { return nil }
        return hints.first { $0.id == id }?.range
    }

    private func recompute() {
        let settings = fetchDictionary().settings
        hints = SoftHints.analyze(text: text, settings: settings)
    }

    /// Fetch the single EditorDictionary, seeding if missing (mirrors fetchTemplate).
    private func fetchDictionary() -> EditorDictionary {
        if let found = (try? context.fetch(FetchDescriptor<EditorDictionary>()))?.first {
            return found
        }
        EditorDictionarySeeder.seedIfNeeded(in: context)
        return (try? context.fetch(FetchDescriptor<EditorDictionary>()))?.first
            ?? EditorDictionaryDefaults.make()
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/SoftHintsSheet.swift
git commit -m "feat(hints): SoftHintsSheet (highlighted text + list panel)"
```

---

## Task 8: Wire «Подсказки» into TopicWorkspaceView

**Files:**
- Modify: `Views/TopicWorkspaceView.swift`

- [ ] **Step 1: Add state**

Next to the other `@State` sheet flags (near `@State private var showStructure = false`), add:

```swift
    @State private var showHints = false
```

- [ ] **Step 2: Add the sheet presenter**

After the existing `.sheet(isPresented: $showStructure) { StructureEditorSheet(topic: topic) }`, add:

```swift
        .sheet(isPresented: $showHints) { SoftHintsSheet(topic: topic) }
```

- [ ] **Step 3: Add the toolbar button**

In `toolbarContent`, after the «Лог» toolbar item and before «Изображения», add:

```swift
        ToolbarItem { Button { showHints = true } label: { Label("Подсказки", systemImage: "text.magnifyingglass") } }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual check (Xcode Run)**

Open a topic with a generated text version → toolbar «Подсказки» → sheet shows highlighted long sentences/repeats/clichés + list; tapping a list row emphasizes its range; «Закрыть» dismisses; reopening the topic shows the text unchanged (nothing saved).

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift
git commit -m "feat(hints): «Подсказки» toolbar button + sheet in workspace"
```

---

## Task 9: «Словарь правок» editor in TemplatesView

**Files:**
- Modify: `Views/TemplatesView.swift`

- [ ] **Step 1: Add the selection case**

In the private `enum TemplateSelection`, add a case:

```swift
    case editorDictionary(UUID)
```

- [ ] **Step 2: Query + selected accessor**

Add a `@Query` next to the others in `TemplatesView`:

```swift
    @Query private var editorDictionaries: [EditorDictionary]
```

Add a computed accessor next to the other `selected…` ones:

```swift
    private var selectedEditorDictionary: EditorDictionary? {
        guard case .editorDictionary(let id) = selection else { return nil }
        return editorDictionaries.first { $0.uuid == id }
    }
```

- [ ] **Step 3: Add a sidebar section**

In `body`'s `List`, after the `Section("Изображения") { … }` block, add:

```swift
                Section("Подсказки") {
                    ForEach(editorDictionaries) { dict in
                        Text("Словарь правок").tag(TemplateSelection.editorDictionary(dict.uuid))
                    }
                }
```

- [ ] **Step 4: Route detail + ensureSelection**

In `detail`, add a branch before the final `else`:

```swift
        } else if let dict = selectedEditorDictionary {
            EditorDictionaryEditorView(dictionary: dict).id(dict.uuid)
```

In `ensureSelection`, append a final fallback before the closing brace:

```swift
        } else if let first = editorDictionaries.first {
            selection = .editorDictionary(first.uuid)
```

Add an `onChange` next to the existing ones:

```swift
        .onChange(of: editorDictionaries.map(\.uuid)) { _, _ in ensureSelection() }
```

- [ ] **Step 5: Add the editor view**

At the end of `TemplatesView.swift` (after `ImageStylePresetEditorView`), add:

```swift
private struct EditorDictionaryEditorView: View {
    @Bindable var dictionary: EditorDictionary

    @State private var clichesText = ""
    @State private var longLimit = EditorDictionaryDefaults.longSentenceWordLimit
    @State private var window = EditorDictionaryDefaults.repeatWindowWords
    @State private var savedNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Словарь правок").font(.title2).bold()
                Text("Версия: \(dictionary.version)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Используется в окне «Подсказки». Только грубая алгоритмическая проверка, без ИИ.")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Штампы (по одному на строку)").font(.headline)
                TextEditor(text: $clichesText).frame(minHeight: 220).border(.gray.opacity(0.3))

                Text("Пороги").font(.headline)
                Stepper("Длинное предложение: от \(longLimit) слов",
                        value: $longLimit, in: 10...80, step: 1)
                    .frame(maxWidth: 360, alignment: .leading)
                Stepper("Окно повторов: \(window) слов",
                        value: $window, in: 5...80, step: 1)
                    .frame(maxWidth: 360, alignment: .leading)

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
        clichesText = dictionary.clichesText
        longLimit = dictionary.longSentenceWordLimit
        window = dictionary.repeatWindowWords
    }

    private func save() {
        dictionary.clichesText = clichesText
        dictionary.longSentenceWordLimit = longLimit
        dictionary.repeatWindowWords = window
        dictionary.version += 1
        dictionary.updatedAt = .now
        savedNote = "Сохранено (версия \(dictionary.version))"
    }

    private func resetToDefault() {
        clichesText = EditorDictionaryDefaults.clichesText
        longLimit = EditorDictionaryDefaults.longSentenceWordLimit
        window = EditorDictionaryDefaults.repeatWindowWords
        save()
        savedNote = "Сброшено к стандартному"
    }
}
```

- [ ] **Step 6: Build to verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Manual check (Xcode Run)**

«Шаблоны» → секция «Подсказки» → «Словарь правок»: edit a cliché line, change thresholds, «Сохранить»; reopen «Подсказки» on a topic and confirm the change takes effect; «Сбросить к стандартному» restores defaults.

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift
git commit -m "feat(hints): «Словарь правок» editor in Templates"
```

---

## Final verification

- [ ] `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS'` → BUILD SUCCEEDED.
- [ ] Xcode Cmd+U → all `SoftHintsTests` green; existing suites still green.
- [ ] Manual: «Подсказки» highlights all three hint types; list selection emphasizes; nothing is saved; dictionary edits in «Шаблоны» take effect; reset works.
- [ ] Then propose `task-finish` (changelog entry, push branch, optional PR).

## Spec coverage check

- Long sentences → Task 1. ✅
- Repeated roots nearby → Task 2. ✅
- Clichés from editable dictionary → Task 3 (detection) + Task 9 (editing). ✅
- Editable dictionary stored, seeded, reset-to-default → Tasks 4, 5, 9. ✅
- Sheet placement, read-only, nothing saved → Tasks 7, 8. ✅
- Multi-range highlight + list panel with select → Tasks 6, 7. ✅
- New additive SwiftData model (low migration risk) → Tasks 4, 5. ✅
- Tests on pure analyzer → Tasks 1–4. ✅
- Out of scope (items 1–2, AI, auto-fix) → not in any task. ✅
