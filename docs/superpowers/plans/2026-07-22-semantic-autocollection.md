# Semantic Auto-Collection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mock semantic collector with a one-click pipeline that plans seed phrases with an LLM, pulls real queries from the Yandex Wordstat API, cleans them through a three-layer funnel, and shows every drop with its reason.

**Architecture:** A pure rule filter does the cheap work offline; two focused LLM services handle relevance and cannibalization separately; a runner orchestrates the layers and writes a per-run funnel journal. Network and LLM access sit behind provider closures so every layer is testable offline, matching the existing `StageExecutor.StreamProvider` pattern.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing (`import Testing`, `#expect`), macOS target.

**Source of truth:** `docs/superpowers/specs/2026-07-22-semantic-autocollection-design.md`

---

## Conventions For Every Task

**New files need no project edits.** The Xcode project uses file-system-synchronized groups, so a new `.swift` file under `SEOContentCreator/SEOContentCreator/` or `SEOContentCreator/SEOContentCreatorTests/` is picked up on the next build.

**Compile check (works in terminal):**

```bash
cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5
```

**Running tests:** `xcodebuild test` hangs in this environment. Run tests with Cmd+U in Xcode, or filter to one suite in the Test navigator. Every "run tests" step below means: compile via the command above, then run via Cmd+U and read the result. Do not report a test as passing unless it actually ran.

---

## Type Contracts

These types are used across tasks. Names must match exactly.

| Type | Defined in Task | Shape |
|---|---|---|
| `WordstatPhrase` | 2 | `struct { text: String, frequency: Int }` |
| `WordstatProvider` | 2 | `(_ seed: String) async throws -> [WordstatPhrase]` |
| `SemanticDroppedPhrase` | 3 | `struct { phrase: WordstatPhrase, reason: String }` |
| `SemanticRuleFilterResult` | 3 | `struct { survivors: [WordstatPhrase], dropped: [SemanticDroppedPhrase] }` |
| `SemanticSeedPlan` | 6 | `struct { synonyms: [String], masks: [String], tails: [String] }` |
| `SemanticFunnelLayer` | 5 | enum: `raw`, `droppedByRules`, `droppedByRelevance`, `droppedByCannibalization`, `survived` |
| `SemanticAgentAnalysis` | 8 | `struct { keywords: [SemanticAgentKeywordResult], longTail: [String] }` |
| `SemanticCannibalizationResult` | 9 | `struct { query: String, risk: SemanticCannibalizationRisk, url: String?, title: String? }` |

`SemanticAgentKeywordResult`, `SemanticAgentRecommendation`, `SemanticReasonCategory`, `SemanticCannibalizationRisk`, and `SemanticUserDecision` already exist and are not redefined.

---

### Task 1: Verify Wordstat API access and capture a fixture

This task writes no production code. It exists because the design was approved with the Wordstat API unverified. If it fails, stop and report to the user before starting Task 2.

**Files:**
- Create: `docs/superpowers/notes/2026-07-22-wordstat-api.md`
- Create: `SEOContentCreator/SEOContentCreatorTests/Fixtures/wordstat-sample.json`

- [ ] **Step 1: Read the current API documentation**

Fetch and read the official Yandex Wordstat API documentation. Record, in your own words:

- the base endpoint URL and HTTP method;
- how a request is authorized (OAuth token, API key, header name);
- the request body or query parameters for pulling including-phrases for one seed;
- how region and device filters are expressed;
- the free-tier quota: requests per day and per hour;
- the exact JSON response shape for a phrase list with frequencies.

- [ ] **Step 2: Make one real request**

Obtain a token (ask the user — do not guess at credentials, and never write a real token into a file in the repo). Make one request for the seed phrase `рак молочной железы`.

```bash
# Fill endpoint, header name, and body from Step 1. Token comes from the user.
curl -s -X POST '<ENDPOINT>' \
  -H 'Authorization: Bearer <TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{"phrase":"рак молочной железы"}' | tee /tmp/wordstat-raw.json | head -40
```

- [ ] **Step 3: Save the response as a test fixture**

Strip anything account-specific, then save the trimmed response (keep 5-10 phrases, enough to exercise the parser):

```bash
cp /tmp/wordstat-raw.json SEOContentCreator/SEOContentCreatorTests/Fixtures/wordstat-sample.json
```

Confirm no token, account id, or login appears in the file:

```bash
grep -iE 'token|bearer|login|account' SEOContentCreator/SEOContentCreatorTests/Fixtures/wordstat-sample.json
```

Expected: no output.

- [ ] **Step 4: Write the findings note**

Create `docs/superpowers/notes/2026-07-22-wordstat-api.md` with: endpoint, auth mechanism, request shape, region and device parameters, quota numbers, response shape, and the JSON path to each phrase's text and frequency. Task 10 reads this note and nothing else.

- [ ] **Step 5: Decide whether to continue**

If the free tier gives fewer than roughly 50 requests per day, or if authorization requires anything the user does not already have, **stop and report to the user**. One collection run needs one request per seed phrase, and a plan produces on the order of 15-30 seeds.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/notes/2026-07-22-wordstat-api.md SEOContentCreator/SEOContentCreatorTests/Fixtures/wordstat-sample.json
git commit -m "docs: record Wordstat API shape and capture response fixture"
```

---

### Task 2: WordstatPhrase value type and provider contract

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/WordstatProvider.swift`

- [ ] **Step 1: Write the type**

This is a plain value type with no behavior, so it gets no dedicated test; Tasks 3 and 10 exercise it.

```swift
import Foundation

/// One phrase returned by Wordstat, with its monthly impression count.
struct WordstatPhrase: Equatable, Sendable {
    var text: String
    var frequency: Int
}

/// Pulls including-phrases for one seed. Injected so layers stay testable offline.
typealias WordstatProvider = @Sendable (_ seed: String) async throws -> [WordstatPhrase]
```

- [ ] **Step 2: Compile**

```bash
cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/WordstatProvider.swift
git commit -m "feat: add Wordstat phrase type and provider contract"
```

---

### Task 3: SemanticRuleFilter — the rule layer

The heart of the funnel: pure, offline, fully testable. Order matters — the top-100 cut runs **after** minus-words and the threshold, so high-frequency academic queries do not consume slots.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticRuleFilter.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticRuleFilterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SEOContentCreator

struct SemanticRuleFilterTests {
    private func phrase(_ text: String, _ frequency: Int) -> WordstatPhrase {
        WordstatPhrase(text: text, frequency: frequency)
    }

    @Test func removesStopWordMatches() {
        let input = [phrase("рак молочной железы реферат", 900), phrase("рак молочной железы лечение", 800)]

        let result = SemanticRuleFilter.apply(input, stopWords: ["реферат"], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["рак молочной железы лечение"])
        #expect(result.dropped.count == 1)
        #expect(result.dropped[0].reason.contains("реферат"))
    }

    @Test func stopWordMatchesWholeWordsOnly() {
        // "тест" must not remove "тестостерон".
        let input = [phrase("тестостерон норма", 500)]

        let result = SemanticRuleFilter.apply(input, stopWords: ["тест"], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["тестостерон норма"])
    }

    @Test func dropsBelowThreshold() {
        let input = [phrase("редкий запрос", 4), phrase("частый запрос", 40)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["частый запрос"])
        #expect(result.dropped[0].reason.contains("частотность"))
    }

    @Test func mergesDuplicatesKeepingHighestFrequency() {
        let input = [phrase("Рак  Груди", 100), phrase("рак груди", 300)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.count == 1)
        #expect(result.survivors[0].frequency == 300)
    }

    @Test func treatsYoAndYeAsSameWord() {
        let input = [phrase("причёска", 50), phrase("прическа", 70)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.count == 1)
    }

    @Test func cutRunsAfterRulesSoLimitIsFilled() {
        // 3 high-frequency academic queries plus 100 usable ones, limit 100.
        var input = [
            phrase("тема реферат", 10_000),
            phrase("тема курсовая", 9_000),
            phrase("тема презентация", 8_000)
        ]
        for index in 0..<100 {
            input.append(phrase("полезный запрос \(index)", 1_000 - index))
        }

        let result = SemanticRuleFilter.apply(input, stopWords: ["реферат", "курсовая", "презентация"], threshold: 10, limit: 100)

        #expect(result.survivors.count == 100)
        #expect(result.survivors.allSatisfy { $0.text.hasPrefix("полезный") })
    }

    @Test func sortsSurvivorsByFrequencyDescending() {
        let input = [phrase("низкий", 20), phrase("высокий", 900), phrase("средний", 100)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 100)

        #expect(result.survivors.map(\.text) == ["высокий", "средний", "низкий"])
    }

    @Test func recordsPhrasesCutByLimitAsDropped() {
        let input = [phrase("первый", 100), phrase("второй", 50)]

        let result = SemanticRuleFilter.apply(input, stopWords: [], threshold: 10, limit: 1)

        #expect(result.survivors.map(\.text) == ["первый"])
        #expect(result.dropped.map(\.phrase.text) == ["второй"])
        #expect(result.dropped[0].reason.contains("топ-1"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Compile with the command from Conventions. Expected: build fails with "cannot find 'SemanticRuleFilter' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

struct SemanticDroppedPhrase: Equatable, Sendable {
    var phrase: WordstatPhrase
    var reason: String
}

struct SemanticRuleFilterResult: Equatable, Sendable {
    var survivors: [WordstatPhrase]
    var dropped: [SemanticDroppedPhrase]
}

/// Layer 1 of the funnel: cheap, offline, deterministic.
/// Order is deliberate — the limit is applied last so junk does not consume slots.
enum SemanticRuleFilter {
    static func apply(
        _ phrases: [WordstatPhrase],
        stopWords: [String],
        threshold: Int,
        limit: Int
    ) -> SemanticRuleFilterResult {
        var dropped: [SemanticDroppedPhrase] = []
        var byKey: [String: WordstatPhrase] = [:]
        var order: [String] = []

        let normalizedStopWords = stopWords
            .map(normalize)
            .filter { !$0.isEmpty }

        for phrase in phrases {
            let key = normalize(phrase.text)
            guard !key.isEmpty else { continue }

            if let matched = normalizedStopWords.first(where: { containsWord($0, in: key) }) {
                dropped.append(SemanticDroppedPhrase(phrase: phrase, reason: "минус-слово «\(matched)»"))
                continue
            }

            if phrase.frequency < threshold {
                dropped.append(SemanticDroppedPhrase(
                    phrase: phrase,
                    reason: "частотность \(phrase.frequency) ниже порога \(threshold)"
                ))
                continue
            }

            if let existing = byKey[key] {
                byKey[key] = WordstatPhrase(text: existing.text, frequency: max(existing.frequency, phrase.frequency))
            } else {
                byKey[key] = phrase
                order.append(key)
            }
        }

        let deduplicated = order.compactMap { byKey[$0] }
        let sorted = deduplicated.sorted { $0.frequency > $1.frequency }

        guard sorted.count > limit else {
            return SemanticRuleFilterResult(survivors: sorted, dropped: dropped)
        }

        for phrase in sorted[limit...] {
            dropped.append(SemanticDroppedPhrase(phrase: phrase, reason: "не вошёл в топ-\(limit) по частотности"))
        }

        return SemanticRuleFilterResult(survivors: Array(sorted[..<limit]), dropped: dropped)
    }

    /// Lowercases, unifies ё/е, and collapses whitespace so duplicates match.
    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Whole-word match, so "тест" does not remove "тестостерон".
    private static func containsWord(_ word: String, in normalizedText: String) -> Bool {
        normalizedText.split(separator: " ").contains { $0 == word }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Compile, then run `SemanticRuleFilterTests` with Cmd+U. Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticRuleFilter.swift SEOContentCreator/SEOContentCreatorTests/SemanticRuleFilterTests.swift
git commit -m "feat: add rule layer for semantic collection funnel"
```

---

### Task 4: Minus-word and question-mask reference lists

Two SwiftData models with seeders, following the existing `ForbiddenPhrase` + `ForbiddenPhraseSeeder` pattern.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/SemanticStopWord.swift`
- Create: `SEOContentCreator/SEOContentCreator/Models/SemanticQueryMask.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticReferenceSeeder.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift:10-19`
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift:34-40`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticReferenceSeederTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct SemanticReferenceSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SemanticStopWord.self, SemanticQueryMask.self, configurations: config)
        return ModelContext(container)
    }

    @Test func seedsStopWordsWhenEmpty() throws {
        let context = try makeContext()
        SemanticReferenceSeeder.seedIfNeeded(in: context)
        let words = try context.fetch(FetchDescriptor<SemanticStopWord>())
        #expect(words.count == SemanticStopWordDefaults.all.count)
        #expect(words.allSatisfy { $0.isEnabled })
    }

    @Test func seedsMasksWhenEmpty() throws {
        let context = try makeContext()
        SemanticReferenceSeeder.seedIfNeeded(in: context)
        let masks = try context.fetch(FetchDescriptor<SemanticQueryMask>())
        #expect(masks.count == SemanticQueryMaskDefaults.all.count)
    }

    @Test func doesNotDuplicateOnSecondRun() throws {
        let context = try makeContext()
        SemanticReferenceSeeder.seedIfNeeded(in: context)
        SemanticReferenceSeeder.seedIfNeeded(in: context)
        let words = try context.fetch(FetchDescriptor<SemanticStopWord>())
        let masks = try context.fetch(FetchDescriptor<SemanticQueryMask>())
        #expect(words.count == SemanticStopWordDefaults.all.count)
        #expect(masks.count == SemanticQueryMaskDefaults.all.count)
    }

    @Test func defaultsCoverAcademicQueries() {
        #expect(SemanticStopWordDefaults.all.contains("реферат"))
        #expect(SemanticStopWordDefaults.all.contains("патогенез"))
        #expect(SemanticQueryMaskDefaults.all.contains("как"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Compile. Expected: "cannot find 'SemanticStopWord' in scope".

- [ ] **Step 3: Write the models**

`SemanticStopWord.swift`:

```swift
import Foundation
import SwiftData

/// A word that removes a query from the funnel at the rule layer.
/// Global across topics — see the design doc's note on drift.
@Model
final class SemanticStopWord {
    var uuid: UUID
    var text: String
    var isEnabled: Bool
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(text: String, order: Int, isEnabled: Bool = true) {
        self.uuid = UUID()
        self.text = text
        self.isEnabled = isEnabled
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

`SemanticQueryMask.swift`:

```swift
import Foundation
import SwiftData

/// A question word the seed planner may combine with the topic.
@Model
final class SemanticQueryMask {
    var uuid: UUID
    var text: String
    var isEnabled: Bool
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(text: String, order: Int, isEnabled: Bool = true) {
        self.uuid = UUID()
        self.text = text
        self.isEnabled = isEnabled
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

- [ ] **Step 4: Write the defaults and seeder**

`SemanticReferenceSeeder.swift`:

```swift
import Foundation
import SwiftData

enum SemanticStopWordDefaults {
    /// Academic and student queries that look relevant but never convert.
    static let all: [String] = [
        "реферат", "курсовая", "диссертация", "презентация", "лекция",
        "конспект", "шпаргалка", "тест", "задача", "учебник",
        "патогенез", "этиология", "классификация", "мкб", "гистология"
    ]
}

enum SemanticQueryMaskDefaults {
    /// Question words from the semantic-core methodology.
    static let all: [String] = [
        "как", "где", "зачем", "что", "сколько", "почему", "куда",
        "кто", "чей", "когда", "какой", "какая", "какое", "какие", "который"
    ]
}

enum SemanticReferenceSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existingWords = (try? context.fetch(FetchDescriptor<SemanticStopWord>())) ?? []
        if existingWords.isEmpty {
            for (index, text) in SemanticStopWordDefaults.all.enumerated() {
                context.insert(SemanticStopWord(text: text, order: index))
            }
        }

        let existingMasks = (try? context.fetch(FetchDescriptor<SemanticQueryMask>())) ?? []
        if existingMasks.isEmpty {
            for (index, text) in SemanticQueryMaskDefaults.all.enumerated() {
                context.insert(SemanticQueryMask(text: text, order: index))
            }
        }
    }
}
```

- [ ] **Step 5: Register the models and the seeder**

In `SEOContentCreatorApp.swift`, add to the `modelContainer(for:)` array after `PromptRecommendation.self`:

```swift
            PersistedRemark.self, PromptRecommendation.self,
            SemanticStopWord.self, SemanticQueryMask.self
```

In `RootView.swift`, add to the `.task` block after `ForbiddenPhraseSeeder.seedIfNeeded(in: context)`:

```swift
            SemanticReferenceSeeder.seedIfNeeded(in: context)
```

- [ ] **Step 6: Run tests to verify they pass**

Compile, then run `SemanticReferenceSeederTests` with Cmd+U. Expected: 4 tests pass.

- [ ] **Step 7: Verify the existing database still opens**

Launch the app (Cmd+R). Open Content Plan and one existing topic. Expected: topics, versions, and semantics load as before. Adding models is additive, but confirm before continuing.

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/SemanticStopWord.swift SEOContentCreator/SEOContentCreator/Models/SemanticQueryMask.swift SEOContentCreator/SEOContentCreator/Logic/SemanticReferenceSeeder.swift SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift SEOContentCreator/SEOContentCreator/Views/RootView.swift SEOContentCreator/SEOContentCreatorTests/SemanticReferenceSeederTests.swift
git commit -m "feat: add minus-word and question-mask reference lists"
```

---

### Task 5: SemanticFunnelEntry journal model

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/SemanticFunnelEntry.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/Topic.swift:39-40`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift:10-19`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticFunnelEntryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct SemanticFunnelEntryTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Topic.self, SemanticFunnelEntry.self, configurations: config)
        return ModelContext(container)
    }

    @Test func storesLayerAndReason() throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let entry = SemanticFunnelEntry(
            text: "рак груди реферат",
            frequency: 900,
            layer: .droppedByRules,
            reason: "минус-слово «реферат»",
            runID: UUID()
        )
        entry.topic = topic
        context.insert(entry)

        let stored = try context.fetch(FetchDescriptor<SemanticFunnelEntry>())
        #expect(stored.count == 1)
        #expect(stored[0].layer == .droppedByRules)
        #expect(stored[0].reason == "минус-слово «реферат»")
    }

    @Test func defaultsToRawLayerOnUnknownValue() throws {
        let context = try makeContext()
        let entry = SemanticFunnelEntry(text: "запрос", frequency: nil, layer: .raw, reason: "", runID: UUID())
        context.insert(entry)

        entry.layerRaw = "мусор из будущей версии"

        #expect(entry.layer == .raw)
    }

    @Test func groupsEntriesByRun() throws {
        let context = try makeContext()
        let firstRun = UUID()
        let secondRun = UUID()
        for runID in [firstRun, firstRun, secondRun] {
            context.insert(SemanticFunnelEntry(text: "q", frequency: 10, layer: .survived, reason: "", runID: runID))
        }

        let stored = try context.fetch(FetchDescriptor<SemanticFunnelEntry>())

        #expect(stored.filter { $0.runID == firstRun }.count == 2)
        #expect(stored.filter { $0.runID == secondRun }.count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Compile. Expected: "cannot find 'SemanticFunnelEntry' in scope".

- [ ] **Step 3: Write the model**

```swift
import Foundation
import SwiftData

/// Where a query left the funnel.
enum SemanticFunnelLayer: String, Codable, CaseIterable {
    case raw
    case droppedByRules
    case droppedByRelevance
    case droppedByCannibalization
    case survived

    var label: String {
        switch self {
        case .raw: return "Собрано из Wordstat"
        case .droppedByRules: return "Отсеяно правилами"
        case .droppedByRelevance: return "Отсеяно по релевантности"
        case .droppedByCannibalization: return "Отсеяно по каннибализации"
        case .survived: return "Прошло в семантику"
        }
    }
}

/// One row of the collection run journal. Kept separate from `SemanticKeyword`
/// so a several-hundred-phrase raw pool does not inflate topic semantics.
@Model
final class SemanticFunnelEntry {
    var uuid: UUID
    var text: String
    var frequency: Int?
    var layerRaw: String
    var reason: String
    var runID: UUID
    var createdAt: Date

    @Relationship var topic: Topic?

    init(text: String, frequency: Int?, layer: SemanticFunnelLayer, reason: String, runID: UUID) {
        self.uuid = UUID()
        self.text = text
        self.frequency = frequency
        self.layerRaw = layer.rawValue
        self.reason = reason
        self.runID = runID
        self.createdAt = .now
    }

    var layer: SemanticFunnelLayer {
        get { SemanticFunnelLayer(rawValue: layerRaw) ?? .raw }
        set { layerRaw = newValue.rawValue }
    }
}
```

- [ ] **Step 4: Add the Topic relationship**

In `Topic.swift`, directly after the `semanticKeywords` relationship (line 39-40):

```swift
    @Relationship(deleteRule: .cascade, inverse: \SemanticFunnelEntry.topic)
    var funnelEntries: [SemanticFunnelEntry] = []
```

- [ ] **Step 5: Register the model**

In `SEOContentCreatorApp.swift`, extend the array added in Task 4:

```swift
            SemanticStopWord.self, SemanticQueryMask.self, SemanticFunnelEntry.self
```

- [ ] **Step 6: Run tests to verify they pass**

Compile, then run `SemanticFunnelEntryTests` with Cmd+U. Expected: 3 tests pass.

- [ ] **Step 7: Verify the existing database still opens**

Launch the app and open an existing topic. Expected: no crash, semantics intact. This task adds a relationship to `Topic`, which is the riskiest migration in the plan.

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/SemanticFunnelEntry.swift SEOContentCreator/SEOContentCreator/Models/Topic.swift SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift SEOContentCreator/SEOContentCreatorTests/SemanticFunnelEntryTests.swift
git commit -m "feat: add semantic funnel journal model"
```

---

### Task 6: Seed plan and its parser

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticSeedPlanParser.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticSeedPlanParserTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SEOContentCreator

struct SemanticSeedPlanParserTests {
    @Test func parsesValidPlan() throws {
        let json = """
        {"synonyms":["рак груди","РМЖ"],"masks":["как","сколько"],"tails":["лечение","цена"]}
        """

        let plan = try SemanticSeedPlanParser.parse(json)

        #expect(plan.synonyms == ["рак груди", "РМЖ"])
        #expect(plan.masks == ["как", "сколько"])
        #expect(plan.tails == ["лечение", "цена"])
    }

    @Test func trimsAndDropsBlankEntries() throws {
        let json = """
        {"synonyms":["  рак груди  ","","РМЖ"],"masks":[],"tails":["   "]}
        """

        let plan = try SemanticSeedPlanParser.parse(json)

        #expect(plan.synonyms == ["рак груди", "РМЖ"])
        #expect(plan.masks.isEmpty)
        #expect(plan.tails.isEmpty)
    }

    @Test func stripsMarkdownFence() throws {
        let json = """
        ```json
        {"synonyms":["РМЖ"],"masks":[],"tails":[]}
        ```
        """

        let plan = try SemanticSeedPlanParser.parse(json)

        #expect(plan.synonyms == ["РМЖ"])
    }

    @Test func throwsOnMalformedJSON() {
        #expect(throws: SemanticSeedPlanParser.ParserError.badResponse) {
            try SemanticSeedPlanParser.parse("не json")
        }
    }

    @Test func throwsWhenAllListsAreEmpty() {
        #expect(throws: SemanticSeedPlanParser.ParserError.badResponse) {
            try SemanticSeedPlanParser.parse("""
            {"synonyms":[],"masks":[],"tails":[]}
            """)
        }
    }

    @Test func buildsSeedPhrasesFromPlan() {
        let plan = SemanticSeedPlan(synonyms: ["рак груди", "РМЖ"], masks: ["как"], tails: ["лечение"])

        let seeds = plan.seedPhrases()

        #expect(seeds.contains("рак груди"))
        #expect(seeds.contains("рак груди лечение"))
        #expect(seeds.contains("рмж как"))
        #expect(Set(seeds).count == seeds.count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Compile. Expected: "cannot find 'SemanticSeedPlanParser' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

struct SemanticSeedPlan: Equatable, Sendable {
    var synonyms: [String]
    var masks: [String]
    var tails: [String]

    /// Every phrase the Wordstat layer will pull, deduplicated and normalized.
    /// Each synonym is pulled bare, plus once per mask and once per tail.
    func seedPhrases() -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for synonym in synonyms {
            let base = SemanticRuleFilter.normalize(synonym)
            guard !base.isEmpty else { continue }

            for candidate in [base] + masks.map { "\(base) \(SemanticRuleFilter.normalize($0))" }
                + tails.map({ "\(base) \(SemanticRuleFilter.normalize($0))" }) {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
                result.append(trimmed)
            }
        }

        return result
    }
}

enum SemanticSeedPlanParser {
    enum ParserError: Error, Equatable {
        case badResponse
    }

    private struct Envelope: Decodable {
        var synonyms: [String]
        var masks: [String]
        var tails: [String]
    }

    static func parse(_ text: String) throws -> SemanticSeedPlan {
        let cleaned = stripFence(text)

        guard let data = cleaned.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ParserError.badResponse
        }

        let plan = SemanticSeedPlan(
            synonyms: clean(envelope.synonyms),
            masks: clean(envelope.masks),
            tails: clean(envelope.tails)
        )

        guard !plan.synonyms.isEmpty || !plan.masks.isEmpty || !plan.tails.isEmpty else {
            throw ParserError.badResponse
        }

        return plan
    }

    private static func clean(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Models sometimes wrap JSON in a Markdown fence despite instructions.
    private static func stripFence(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.hasPrefix("```") else { return result }

        result = result
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Compile, then run `SemanticSeedPlanParserTests` with Cmd+U. Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticSeedPlanParser.swift SEOContentCreator/SEOContentCreatorTests/SemanticSeedPlanParserTests.swift
git commit -m "feat: add semantic seed plan and parser"
```

---

### Task 7: SemanticSeedPlanner service

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticSeedPlanner.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticSeedPlannerTests.swift`

Read `SemanticAgentAnalyzer.swift:19-64` first — this service copies its provider-injection shape exactly.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import SEOContentCreator

@MainActor
struct SemanticSeedPlannerTests {
    private func makePlanner(response: String) -> SemanticSeedPlanner {
        SemanticSeedPlanner(
            streamProvider: { _, _, _, _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.token(response))
                    continuation.finish()
                }
            },
            keyProvider: { "test-key" },
            model: "gpt-4.1"
        )
    }

    @Test func returnsParsedPlan() async throws {
        let planner = makePlanner(response: """
        {"synonyms":["рак груди"],"masks":["как"],"tails":["лечение"]}
        """)
        let topic = Topic(title: "Рак молочной железы", articleType: .disease)

        let plan = try await planner.plan(topic: topic, masks: ["как", "где"])

        #expect(plan.synonyms == ["рак груди"])
    }

    @Test func throwsOnEmptyResponse() async {
        let planner = makePlanner(response: "   ")
        let topic = Topic(title: "Рак молочной железы", articleType: .disease)

        await #expect(throws: SemanticSeedPlanner.PlannerError.emptyResponse) {
            _ = try await planner.plan(topic: topic, masks: [])
        }
    }

    @Test func promptListsAllowedMasks() {
        let topic = Topic(title: "Рак молочной железы", articleType: .disease)

        let prompt = SemanticSeedPlanner.userPrompt(topic: topic, masks: ["как", "сколько"])

        #expect(prompt.contains("Рак молочной железы"))
        #expect(prompt.contains("как"))
        #expect(prompt.contains("сколько"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Compile. Expected: "cannot find 'SemanticSeedPlanner' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Layer 1 of the pipeline: turns a topic into the seed phrases to pull from Wordstat.
@MainActor
struct SemanticSeedPlanner {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = StageExecutor.KeyProvider

    enum PlannerError: Error, LocalizedError, Equatable {
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "Агент не вернул план сбора. Попробуйте ещё раз."
            }
        }
    }

    let streamProvider: StreamProvider
    let keyProvider: KeyProvider
    let model: String

    static func live(model: String) -> SemanticSeedPlanner {
        SemanticSeedPlanner(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens, reasoningEffort in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey,
                    system: system,
                    user: user,
                    model: model,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    reasoningEffort: reasoningEffort
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() },
            model: model
        )
    }

    func plan(topic: Topic, masks: [String]) async throws -> SemanticSeedPlan {
        let key = try keyProvider()
        var collected = ""

        for try await event in streamProvider(
            key,
            Self.systemPrompt,
            Self.userPrompt(topic: topic, masks: masks),
            model,
            0.3,
            2000,
            nil
        ) {
            if case .token(let token) = event {
                collected += token
            }
        }

        guard !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlannerError.emptyResponse
        }

        return try SemanticSeedPlanParser.parse(collected)
    }

    static let systemPrompt = """
    Ты SEO-аналитик медицинской клиники. Верни только JSON без Markdown.
    Твоя задача — спланировать сбор семантики: какие фразы отправить в Wordstat.
    Не выдумывай вопросительные слова: бери только из предложенного списка.
    """

    static func userPrompt(topic: Topic, masks: [String]) -> String {
        """
        Тема: \(topic.title)
        Тип статьи: \(topic.articleType.title)

        Разрешённые вопросительные слова:
        \(masks.joined(separator: ", "))

        Верни JSON:
        {"synonyms":["варианты названия темы: сокращения, разговорные и профессиональные термины, латиница и кириллица"],"masks":["вопросительные слова из списка выше, подходящие теме"],"tails":["уточнения: лечение, цена, симптомы, отзывы, гео — подходящие именно этой теме"]}
        """
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Compile, then run `SemanticSeedPlannerTests` with Cmd+U. Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticSeedPlanner.swift SEOContentCreator/SEOContentCreatorTests/SemanticSeedPlannerTests.swift
git commit -m "feat: add semantic seed planner agent"
```

---

### Task 8: Narrow the relevance analyzer and add long-tail output

`SemanticAgentAnalyzer` currently judges relevance and cannibalization in one prompt. Cannibalization moves to Task 9. Here the analyzer gains long-tail generation and loses responsibility for cannibalization.

`SemanticAgentKeywordResult` keeps its cannibalization fields — the relevance layer leaves them at `.none`/`nil`, and Task 9 fills them in. This keeps `SemanticKeywordMerger` unchanged.

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentResponseParser.swift:19-32,34-72`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift:41-88`
- Modify: `SEOContentCreator/SEOContentCreatorTests/SemanticAgentResponseParserTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/SemanticAgentAnalyzerTests.swift`

- [ ] **Step 1: Read the existing tests before changing them**

```bash
cat SEOContentCreator/SEOContentCreatorTests/SemanticAgentResponseParserTests.swift SEOContentCreator/SEOContentCreatorTests/SemanticAgentAnalyzerTests.swift
```

The parser's return type changes from `[SemanticAgentKeywordResult]` to `SemanticAgentAnalysis`. Every existing assertion of the form `result[0].query` becomes `result.keywords[0].query`. Update them all rather than leaving both shapes alive.

- [ ] **Step 2: Add the failing tests**

Append to `SemanticAgentResponseParserTests.swift`:

```swift
    @Test func parsesLongTailQueries() throws {
        let json = """
        {"keywords":[{"query":"рак груди лечение","frequency":100,"recommendation":"include","reasonCategory":"none","explanation":""}],"longTail":["сколько длится лечение рака груди","можно ли вылечить рак груди полностью"]}
        """

        let analysis = try SemanticAgentResponseParser.parse(json)

        #expect(analysis.keywords.count == 1)
        #expect(analysis.longTail.count == 2)
    }

    @Test func defaultsCannibalizationFieldsWhenAbsent() throws {
        let json = """
        {"keywords":[{"query":"рак груди","frequency":null,"recommendation":"include","reasonCategory":"none","explanation":""}]}
        """

        let analysis = try SemanticAgentResponseParser.parse(json)

        #expect(analysis.keywords[0].cannibalizationRisk == .none)
        #expect(analysis.keywords[0].cannibalizationURL == nil)
        #expect(analysis.longTail.isEmpty)
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Compile. Expected: type error — `[SemanticAgentKeywordResult]` has no member `keywords`.

- [ ] **Step 4: Change the parser**

In `SemanticAgentResponseParser.swift`, add the result type above `enum SemanticAgentResponseParser`:

```swift
struct SemanticAgentAnalysis: Equatable {
    var keywords: [SemanticAgentKeywordResult]
    var longTail: [String]
}
```

Replace the `Envelope` and `Item` structs with:

```swift
    private struct Envelope: Decodable {
        var keywords: [Item]
        var longTail: [String]?
    }

    private struct Item: Decodable {
        var query: String
        var frequency: Int?
        var recommendation: String
        var reasonCategory: String
        var explanation: String
        var cannibalizationRisk: String?
        var cannibalizationURL: String?
        var cannibalizationTitle: String?
    }
```

Replace the `parse` signature and its cannibalization decoding:

```swift
    static func parse(_ text: String) throws -> SemanticAgentAnalysis {
        guard let data = text.data(using: .utf8) else {
            throw ParserError.badResponse
        }

        let decoder = JSONDecoder()

        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw ParserError.badResponse
        }

        var results: [SemanticAgentKeywordResult] = []

        for item in envelope.keywords {
            let query = item.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw ParserError.badResponse
            }

            guard let recommendation = SemanticAgentRecommendation(rawValue: item.recommendation),
                  let reasonCategory = SemanticReasonCategory(rawValue: item.reasonCategory),
                  let cannibalizationRisk = SemanticCannibalizationRisk(rawValue: item.cannibalizationRisk ?? "none") else {
                throw ParserError.badResponse
            }

            results.append(SemanticAgentKeywordResult(
                query: query,
                frequency: item.frequency,
                recommendation: recommendation,
                reasonCategory: reasonCategory,
                explanation: item.explanation,
                cannibalizationRisk: cannibalizationRisk,
                cannibalizationURL: item.cannibalizationURL,
                cannibalizationTitle: item.cannibalizationTitle
            ))
        }

        let longTail = (envelope.longTail ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return SemanticAgentAnalysis(keywords: results, longTail: longTail)
    }
```

- [ ] **Step 5: Change the analyzer**

In `SemanticAgentAnalyzer.swift`, change the `analyze` return type and drop the `pages` parameter:

```swift
    func analyze(topic: Topic, queries: [WordstatPhrase]) async throws -> SemanticAgentAnalysis {
```

Inside `analyze`, replace the `userPrompt(topic:queries:pages:)` call with `userPrompt(topic: topic, queries: queries)`, and leave the rest of the streaming loop unchanged.

Replace both prompts:

```swift
    private var systemPrompt: String {
        """
        Ты SEO-аналитик медицинского сайта. Верни только JSON без Markdown.
        Решай, какие запросы стоит включить в семантику темы, а какие не стоит.
        Отклоняй академические и учебные формулировки, а также запросы,
        интент которых не совпадает с типом статьи.
        """
    }

    private func userPrompt(topic: Topic, queries: [WordstatPhrase]) -> String {
        """
        Тема: \(topic.title)
        Тип статьи: \(topic.articleType.title)

        Кандидаты (запрос — частотность):
        \(queries.map { "- \($0.text) — \($0.frequency)" }.joined(separator: "\n"))

        Дополнительно составь 10 длинных запросов из 3-7 слов, которые, по твоему
        мнению, интересны целевой аудитории, и верни их в поле longTail.

        Верни JSON:
        {"keywords":[{"query":"...","frequency":null,"recommendation":"include|exclude","reasonCategory":"none|junk|offTopic|cannibalization|lowQuality|tooBroad|wrongIntent|other","explanation":"короткая причина"}],"longTail":["..."]}
        """
    }
```

- [ ] **Step 6: Update the existing call site so the project compiles**

`SemanticAgentSheet.swift:123` calls the old signature. That view is deleted in Task 12, but the project must compile now. Change line 123 to:

```swift
                let analyzed = try await analyzer.analyze(topic: topic, queries: candidates.map { WordstatPhrase(text: $0, frequency: 0) })
                results = analyzed.keywords
```

- [ ] **Step 7: Run tests to verify they pass**

Compile, then run `SemanticAgentResponseParserTests` and `SemanticAgentAnalyzerTests` with Cmd+U. Expected: all pass, including the two new tests.

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticAgentResponseParser.swift SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift SEOContentCreator/SEOContentCreatorTests/SemanticAgentResponseParserTests.swift SEOContentCreator/SEOContentCreatorTests/SemanticAgentAnalyzerTests.swift
git commit -m "refactor: narrow relevance analyzer and add long-tail output"
```

---

### Task 9: SemanticCannibalizationChecker

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticCannibalizationChecker.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticCannibalizationCheckerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SEOContentCreator

@MainActor
struct SemanticCannibalizationCheckerTests {
    private func makeChecker(response: String) -> SemanticCannibalizationChecker {
        SemanticCannibalizationChecker(
            streamProvider: { _, _, _, _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.token(response))
                    continuation.finish()
                }
            },
            keyProvider: { "test-key" },
            model: "gpt-4.1"
        )
    }

    private func keyword(_ query: String) -> SemanticAgentKeywordResult {
        SemanticAgentKeywordResult(
            query: query,
            frequency: 100,
            recommendation: .include,
            reasonCategory: .none,
            explanation: "",
            cannibalizationRisk: .none,
            cannibalizationURL: nil,
            cannibalizationTitle: nil
        )
    }

    @Test func fillsCannibalizationFields() async throws {
        let checker = makeChecker(response: """
        {"results":[{"query":"рак груди лечение","risk":"high","url":"https://hadassah.moscow/rak-grudi","title":"Лечение рака груди"}]}
        """)

        let updated = try await checker.check(keywords: [keyword("рак груди лечение")], pages: [])

        #expect(updated[0].cannibalizationRisk == .high)
        #expect(updated[0].cannibalizationURL == "https://hadassah.moscow/rak-grudi")
        #expect(updated[0].reasonCategory == .cannibalization)
    }

    @Test func leavesUnmentionedKeywordsUntouched() async throws {
        let checker = makeChecker(response: """
        {"results":[]}
        """)

        let updated = try await checker.check(keywords: [keyword("рак груди лечение")], pages: [])

        #expect(updated[0].cannibalizationRisk == .none)
        #expect(updated[0].reasonCategory == .none)
    }

    @Test func skipsNetworkCallWhenNoPagesAndNoKeywords() async throws {
        let checker = makeChecker(response: "не должно вызываться")

        let updated = try await checker.check(keywords: [], pages: [])

        #expect(updated.isEmpty)
    }

    @Test func lowRiskDoesNotOverwriteReasonCategory() async throws {
        let checker = makeChecker(response: """
        {"results":[{"query":"рак груди лечение","risk":"low","url":null,"title":null}]}
        """)

        let updated = try await checker.check(keywords: [keyword("рак груди лечение")], pages: [])

        #expect(updated[0].cannibalizationRisk == .low)
        #expect(updated[0].reasonCategory == .none)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Compile. Expected: "cannot find 'SemanticCannibalizationChecker' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

struct SemanticCannibalizationResult: Equatable {
    var query: String
    var risk: SemanticCannibalizationRisk
    var url: String?
    var title: String?
}

enum SemanticCannibalizationParser {
    enum ParserError: Error, Equatable {
        case badResponse
    }

    private struct Envelope: Decodable {
        var results: [Item]
    }

    private struct Item: Decodable {
        var query: String
        var risk: String
        var url: String?
        var title: String?
    }

    static func parse(_ text: String) throws -> [SemanticCannibalizationResult] {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ParserError.badResponse
        }

        return try envelope.results.map { item in
            guard let risk = SemanticCannibalizationRisk(rawValue: item.risk) else {
                throw ParserError.badResponse
            }
            return SemanticCannibalizationResult(query: item.query, risk: risk, url: item.url, title: item.title)
        }
    }
}

/// Layer 3 of the funnel. Split from the relevance analyzer so neither prompt
/// grows large enough to degrade the other.
@MainActor
struct SemanticCannibalizationChecker {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = StageExecutor.KeyProvider

    let streamProvider: StreamProvider
    let keyProvider: KeyProvider
    let model: String

    static func live(model: String) -> SemanticCannibalizationChecker {
        SemanticCannibalizationChecker(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens, reasoningEffort in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey,
                    system: system,
                    user: user,
                    model: model,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    reasoningEffort: reasoningEffort
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() },
            model: model
        )
    }

    func check(
        keywords: [SemanticAgentKeywordResult],
        pages: [PublishedSitePage]
    ) async throws -> [SemanticAgentKeywordResult] {
        guard !keywords.isEmpty else { return keywords }

        let key = try keyProvider()
        var collected = ""

        for try await event in streamProvider(
            key,
            Self.systemPrompt,
            Self.userPrompt(keywords: keywords, pages: pages),
            model,
            0.2,
            3000,
            nil
        ) {
            if case .token(let token) = event {
                collected += token
            }
        }

        let results = try SemanticCannibalizationParser.parse(collected)
        let byQuery = Dictionary(results.map { ($0.query, $0) }, uniquingKeysWith: { first, _ in first })

        return keywords.map { keyword in
            guard let match = byQuery[keyword.query] else { return keyword }

            var updated = keyword
            updated.cannibalizationRisk = match.risk
            updated.cannibalizationURL = match.url
            updated.cannibalizationTitle = match.title
            // Only a serious clash rewrites the reason the editor sees.
            if match.risk == .high || match.risk == .medium {
                updated.reasonCategory = .cannibalization
            }
            return updated
        }
    }

    static let systemPrompt = """
    Ты SEO-аналитик медицинского сайта. Верни только JSON без Markdown.
    Оцени, конкурирует ли каждый запрос с уже опубликованными страницами сайта.
    Если конкуренции нет, не включай запрос в ответ.
    """

    static func userPrompt(keywords: [SemanticAgentKeywordResult], pages: [PublishedSitePage]) -> String {
        """
        Запросы:
        \(keywords.map { "- \($0.query)" }.joined(separator: "\n"))

        Опубликованные страницы сайта:
        \(pages.map(\.summaryForAgent).joined(separator: "\n\n---\n\n"))

        Верни JSON:
        {"results":[{"query":"...","risk":"low|medium|high","url":"адрес конкурирующей страницы или null","title":"заголовок или null"}]}
        """
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Compile, then run `SemanticCannibalizationCheckerTests` with Cmd+U. Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticCannibalizationChecker.swift SEOContentCreator/SEOContentCreatorTests/SemanticCannibalizationCheckerTests.swift
git commit -m "feat: add standalone cannibalization checker"
```

---

### Task 10: Real Wordstat client

Do not start until Task 1 is complete. Read `docs/superpowers/notes/2026-07-22-wordstat-api.md` and use the recorded endpoint, auth, and response shape. The code below is the shape the rest of the plan depends on; the request construction and the `Response` decoding structs must match the note, not this sketch.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/WordstatClient.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/WordstatCredentialStore.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/WordstatResponseParserTests.swift`

- [ ] **Step 1: Write the failing parser test using the Task 1 fixture**

Adjust the expected values to match the phrases actually present in your fixture.

```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct WordstatResponseParserTests {
    private func fixture() throws -> Data {
        let url = Bundle(for: BundleMarker.self)
            .url(forResource: "wordstat-sample", withExtension: "json")
        let path = try #require(url)
        return try Data(contentsOf: path)
    }

    @Test func parsesPhrasesWithFrequencies() throws {
        let phrases = try WordstatResponseParser.parse(fixture())

        #expect(!phrases.isEmpty)
        #expect(phrases.allSatisfy { !$0.text.isEmpty })
        #expect(phrases.allSatisfy { $0.frequency >= 0 })
    }

    @Test func throwsOnMalformedJSON() {
        let data = Data("не json".utf8)

        #expect(throws: WordstatResponseParser.ParserError.badResponse) {
            try WordstatResponseParser.parse(data)
        }
    }
}

/// Anchors `Bundle(for:)` to the test bundle so the fixture resolves.
private final class BundleMarker {}
```

- [ ] **Step 2: Run test to verify it fails**

Compile. Expected: "cannot find 'WordstatResponseParser' in scope".

- [ ] **Step 3: Write the parser and client**

Fill `Response` and the `phrases` mapping from the Task 1 note.

```swift
import Foundation

enum WordstatResponseParser {
    enum ParserError: Error, Equatable {
        case badResponse
    }

    /// Shape comes from docs/superpowers/notes/2026-07-22-wordstat-api.md.
    /// Adjust the coding keys there rather than guessing here.
    private struct Response: Decodable {
        struct Phrase: Decodable {
            var phrase: String
            var count: Int
        }
        var includingPhrases: [Phrase]
    }

    static func parse(_ data: Data) throws -> [WordstatPhrase] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ParserError.badResponse
        }

        return response.includingPhrases.compactMap { item in
            let text = item.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return WordstatPhrase(text: text, frequency: max(0, item.count))
        }
    }
}

struct WordstatClient {
    enum ClientError: Error, LocalizedError, Equatable {
        case missingToken
        case quotaExceeded
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "Не задан токен Wordstat. Добавьте его в настройках."
            case .quotaExceeded:
                return "Исчерпан дневной лимит запросов к Wordstat. Попробуйте завтра."
            case .httpError(let code):
                return "Wordstat вернул ошибку \(code)."
            }
        }
    }

    /// Moscow and Moscow region, all devices — the confirmed defaults.
    static let defaultRegions = [1, 213]

    var token: String
    var session: URLSession = .shared

    func phrases(for seed: String) async throws -> [WordstatPhrase] {
        guard !token.isEmpty else { throw ClientError.missingToken }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "phrase": seed,
            "regions": Self.defaultRegions
        ])

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? ClientError.quotaExceeded : ClientError.httpError(http.statusCode)
        }

        return try WordstatResponseParser.parse(data)
    }

    /// Endpoint from the Task 1 note.
    static let endpoint = URL(string: "https://api.wordstat.yandex.net/v1/topRequests")!

    func provider() -> WordstatProvider {
        { seed in try await phrases(for: seed) }
    }
}
```

`WordstatCredentialStore.swift` — read `KeychainService.swift` first and mirror its API for a second key named `wordstatToken`:

```swift
import Foundation

/// Stores the Wordstat token alongside the OpenAI key, using the same Keychain path.
enum WordstatCredentialStore {
    private static let account = "wordstatToken"

    static func save(_ token: String) throws {
        try KeychainService.save(token, account: account)
    }

    static func load() throws -> String {
        try KeychainService.load(account: account)
    }
}
```

If `KeychainService` does not expose `save(_:account:)` and `load(account:)`, add those overloads there rather than duplicating Keychain code.

- [ ] **Step 4: Run tests to verify they pass**

Compile, then run `WordstatResponseParserTests` with Cmd+U. Expected: 2 tests pass.

- [ ] **Step 5: Verify against the live API once**

Add a temporary scratch call in the app, or use `curl` with the same body the client builds, and confirm the parser handles the live response. Remove any scratch code before committing.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/WordstatClient.swift SEOContentCreator/SEOContentCreator/Logic/WordstatCredentialStore.swift SEOContentCreator/SEOContentCreatorTests/WordstatResponseParserTests.swift
git commit -m "feat: add Wordstat API client and response parser"
```

---

### Task 11: SemanticCollectionRunner orchestrator

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordMerger.swift:4-35`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticKeywordMergerTests.swift` (extend)

- [ ] **Step 1: Write the failing merger test**

Append to `SemanticKeywordMergerTests.swift`:

```swift
    @Test func savesSurvivorsAsAcceptedWhenRequested() {
        let topic = Topic(title: "Рак груди", articleType: .disease)
        let result = SemanticAgentKeywordResult(
            query: "рак груди лечение",
            frequency: 500,
            recommendation: .include,
            reasonCategory: .none,
            explanation: "",
            cannibalizationRisk: .none,
            cannibalizationURL: nil,
            cannibalizationTitle: nil
        )

        SemanticKeywordMerger.merge([result], into: topic, decision: .accepted)

        #expect(topic.semanticKeywords[0].userDecision == .accepted)
    }

    @Test func doesNotOverwriteDecisionTheUserAlreadyMade() {
        let topic = Topic(title: "Рак груди", articleType: .disease)
        let existing = SemanticKeyword(text: "рак груди лечение", userDecision: .rejected)
        existing.topic = topic
        topic.semanticKeywords.append(existing)

        let result = SemanticAgentKeywordResult(
            query: "рак груди лечение",
            frequency: 500,
            recommendation: .include,
            reasonCategory: .none,
            explanation: "",
            cannibalizationRisk: .none,
            cannibalizationURL: nil,
            cannibalizationTitle: nil
        )

        SemanticKeywordMerger.merge([result], into: topic, decision: .accepted)

        #expect(existing.userDecision == .rejected)
        #expect(existing.frequency == 500)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Compile. Expected: "extra argument 'decision' in call".

- [ ] **Step 3: Change the merger**

In `SemanticKeywordMerger.swift`, change the signature and the two branches:

```swift
    static func merge(
        _ results: [SemanticAgentKeywordResult],
        into topic: Topic,
        decision: SemanticUserDecision = .pending
    ) {
        for result in results {
            let normalized = normalize(result.query)

            if let existing = topic.semanticKeywords.first(where: { normalize($0.text) == normalized }) {
                existing.frequency = result.frequency
                existing.agentRecommendation = result.recommendation
                existing.reasonCategory = result.reasonCategory
                existing.explanation = result.explanation
                existing.cannibalizationRisk = result.cannibalizationRisk
                existing.cannibalizationURL = result.cannibalizationURL
                existing.cannibalizationTitle = result.cannibalizationTitle
                // A decision the user already made is never overwritten by a re-run.
                if existing.userDecision == .pending {
                    existing.userDecision = decision
                }
                existing.updatedAt = .now
            } else {
                let keyword = SemanticKeyword(
                    text: result.query.trimmingCharacters(in: .whitespacesAndNewlines),
                    frequency: result.frequency,
                    agentRecommendation: result.recommendation,
                    userDecision: decision,
                    reasonCategory: result.reasonCategory,
                    explanation: result.explanation,
                    cannibalizationRisk: result.cannibalizationRisk,
                    cannibalizationURL: result.cannibalizationURL,
                    cannibalizationTitle: result.cannibalizationTitle
                )
                keyword.topic = topic
                topic.semanticKeywords.append(keyword)
            }
        }

        topic.updatedAt = .now
    }
```

- [ ] **Step 4: Write the failing runner test**

```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct SemanticCollectionRunnerTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, SemanticKeyword.self, SemanticFunnelEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeRunner(
        plan: SemanticSeedPlan = SemanticSeedPlan(synonyms: ["рак груди"], masks: [], tails: []),
        pulled: [WordstatPhrase],
        analysis: SemanticAgentAnalysis
    ) -> SemanticCollectionRunner {
        SemanticCollectionRunner(
            planSeeds: { _, _ in plan },
            pullPhrases: { _ in pulled },
            analyzeRelevance: { _, _ in analysis },
            checkCannibalization: { keywords, _ in keywords },
            stopWords: ["реферат"],
            masks: ["как"],
            threshold: 10,
            limit: 100
        )
    }

    private func includedResult(_ query: String) -> SemanticAgentKeywordResult {
        SemanticAgentKeywordResult(
            query: query, frequency: nil, recommendation: .include, reasonCategory: .none,
            explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
        )
    }

    @Test func savesSurvivorsAsAcceptedKeywords() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
            analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(topic.semanticKeywords.map(\.text) == ["рак груди лечение"])
        #expect(topic.semanticKeywords[0].userDecision == .accepted)
    }

    @Test func recordsRuleDropsInFunnel() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [
                WordstatPhrase(text: "рак груди реферат", frequency: 900),
                WordstatPhrase(text: "рак груди лечение", frequency: 500)
            ],
            analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        let dropped = topic.funnelEntries.filter { $0.layer == .droppedByRules }
        #expect(dropped.map(\.text) == ["рак груди реферат"])
        #expect(dropped[0].reason.contains("реферат"))
    }

    @Test func recordsRelevanceDropsInFunnel() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        var excluded = includedResult("рак груди форум")
        excluded.recommendation = .exclude
        excluded.reasonCategory = .offTopic

        let runner = makeRunner(
            pulled: [
                WordstatPhrase(text: "рак груди лечение", frequency: 500),
                WordstatPhrase(text: "рак груди форум", frequency: 400)
            ],
            analysis: SemanticAgentAnalysis(
                keywords: [includedResult("рак груди лечение"), excluded],
                longTail: []
            )
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(topic.semanticKeywords.map(\.text) == ["рак груди лечение"])
        #expect(topic.funnelEntries.filter { $0.layer == .droppedByRelevance }.map(\.text) == ["рак груди форум"])
    }

    @Test func addsLongTailQueriesWithoutFrequency() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
            analysis: SemanticAgentAnalysis(
                keywords: [includedResult("рак груди лечение")],
                longTail: ["сколько длится лечение рака груди"]
            )
        )

        try await runner.run(topic: topic, pages: [], context: context)

        let longTail = topic.semanticKeywords.first { $0.text == "сколько длится лечение рака груди" }
        #expect(longTail != nil)
        #expect(longTail?.frequency == nil)
    }

    @Test func groupsEveryEntryUnderOneRunID() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [
                WordstatPhrase(text: "рак груди реферат", frequency: 900),
                WordstatPhrase(text: "рак груди лечение", frequency: 500)
            ],
            analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(Set(topic.funnelEntries.map(\.runID)).count == 1)
    }
}
```

- [ ] **Step 5: Run tests to verify they fail**

Compile. Expected: "cannot find 'SemanticCollectionRunner' in scope".

- [ ] **Step 6: Write the runner**

```swift
import Foundation
import SwiftData

/// Orchestrates the whole collection pipeline. Every external dependency is a
/// closure so the whole run is testable without network or LLM access.
@MainActor
struct SemanticCollectionRunner {
    typealias SeedPlanner = (Topic, [String]) async throws -> SemanticSeedPlan
    typealias PhrasePuller = (String) async throws -> [WordstatPhrase]
    typealias RelevanceAnalyzer = (Topic, [WordstatPhrase]) async throws -> SemanticAgentAnalysis
    typealias CannibalizationCheck = ([SemanticAgentKeywordResult], [PublishedSitePage]) async throws -> [SemanticAgentKeywordResult]

    enum RunError: Error, LocalizedError, Equatable {
        case noPhrasesPulled

        var errorDescription: String? {
            switch self {
            case .noPhrasesPulled:
                return "Wordstat не вернул ни одного запроса. Семантика темы не изменена."
            }
        }
    }

    var planSeeds: SeedPlanner
    var pullPhrases: PhrasePuller
    var analyzeRelevance: RelevanceAnalyzer
    var checkCannibalization: CannibalizationCheck
    var stopWords: [String]
    var masks: [String]
    var threshold: Int
    var limit: Int

    @discardableResult
    func run(topic: Topic, pages: [PublishedSitePage], context: ModelContext) async throws -> UUID {
        let runID = UUID()

        let plan = try await planSeeds(topic, masks)

        var pulled: [WordstatPhrase] = []
        for seed in plan.seedPhrases() {
            // A failing seed must not abort the run; the funnel records the gap.
            guard let phrases = try? await pullPhrases(seed) else {
                record(topic: topic, context: context, text: seed, frequency: nil,
                       layer: .raw, reason: "не удалось выгрузить из Wordstat", runID: runID)
                continue
            }
            pulled.append(contentsOf: phrases)
        }

        guard !pulled.isEmpty else { throw RunError.noPhrasesPulled }

        for phrase in pulled {
            record(topic: topic, context: context, text: phrase.text, frequency: phrase.frequency,
                   layer: .raw, reason: "", runID: runID)
        }

        let filtered = SemanticRuleFilter.apply(pulled, stopWords: stopWords, threshold: threshold, limit: limit)

        for drop in filtered.dropped {
            record(topic: topic, context: context, text: drop.phrase.text, frequency: drop.phrase.frequency,
                   layer: .droppedByRules, reason: drop.reason, runID: runID)
        }

        guard !filtered.survivors.isEmpty else { throw RunError.noPhrasesPulled }

        let analysis = try await analyzeRelevance(topic, filtered.survivors)

        for keyword in analysis.keywords where keyword.recommendation == .exclude {
            record(topic: topic, context: context, text: keyword.query, frequency: keyword.frequency,
                   layer: .droppedByRelevance,
                   reason: keyword.explanation.isEmpty ? keyword.reasonCategory.label : keyword.explanation,
                   runID: runID)
        }

        let included = analysis.keywords.filter { $0.recommendation == .include }
        let checked = try await checkCannibalization(included, pages)

        let longTailResults = analysis.longTail.map { query in
            SemanticAgentKeywordResult(
                query: query, frequency: nil, recommendation: .include, reasonCategory: .none,
                explanation: "Длинный запрос, предложен агентом",
                cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
            )
        }

        let survivors = checked + longTailResults

        for keyword in survivors {
            record(topic: topic, context: context, text: keyword.query, frequency: keyword.frequency,
                   layer: .survived, reason: "", runID: runID)
        }

        SemanticKeywordMerger.merge(survivors, into: topic, decision: .accepted)
        try? context.save()

        return runID
    }

    private func record(
        topic: Topic, context: ModelContext, text: String, frequency: Int?,
        layer: SemanticFunnelLayer, reason: String, runID: UUID
    ) {
        let entry = SemanticFunnelEntry(text: text, frequency: frequency, layer: layer, reason: reason, runID: runID)
        entry.topic = topic
        context.insert(entry)
        topic.funnelEntries.append(entry)
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Compile, then run `SemanticCollectionRunnerTests` and `SemanticKeywordMergerTests` with Cmd+U. Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordMerger.swift SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift SEOContentCreator/SEOContentCreatorTests/SemanticKeywordMergerTests.swift
git commit -m "feat: add semantic collection runner"
```

---

### Task 12: Funnel screen, replacing the agent sheet

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/SemanticFunnelView.swift`
- Delete: `SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift`
- Delete: `SEOContentCreator/SEOContentCreator/Logic/SemanticMockKeywordCollector.swift`
- Delete: `SEOContentCreator/SEOContentCreatorTests/SemanticMockKeywordCollectorTests.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift:126-128`

- [ ] **Step 1: Write the funnel view**

```swift
import SwiftData
import SwiftUI

struct SemanticFunnelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic

    @Query(filter: #Predicate<PublishedSitePage> { $0.siteHost == "hadassah.moscow" })
    private var pages: [PublishedSitePage]
    @Query(sort: \SemanticStopWord.order) private var stopWords: [SemanticStopWord]
    @Query(sort: \SemanticQueryMask.order) private var masks: [SemanticQueryMask]

    @AppStorage("openAIModel") private var model = "gpt-4.1"

    @State private var isRunning = false
    @State private var message: String?
    @State private var runID: UUID?

    private var entries: [SemanticFunnelEntry] {
        guard let runID else { return [] }
        return topic.funnelEntries.filter { $0.runID == runID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сбор семантики").font(.headline)
            Text(topic.title).foregroundStyle(.secondary)

            if pages.isEmpty {
                Text("Индекс страниц сайта пустой. Проверка каннибализации будет неполной.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button(isRunning ? "Собираю…" : "Собрать семантику") { collect() }
                    .disabled(isRunning)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SemanticFunnelLayer.allCases, id: \.self) { layer in
                        layerSection(layer)
                    }
                }
                .padding(.trailing, 8)
            }

            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }
            }
        }
        .padding()
        .frame(width: 760, height: 620)
    }

    @ViewBuilder
    private func layerSection(_ layer: SemanticFunnelLayer) -> some View {
        let rows = entries.filter { $0.layer == layer }

        if !rows.isEmpty {
            DisclosureGroup {
                ForEach(rows, id: \.uuid) { entry in
                    HStack(alignment: .top) {
                        Text(entry.text)
                        Spacer()
                        if let frequency = entry.frequency {
                            Text("\(frequency)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        if !entry.reason.isEmpty {
                            Text(entry.reason).foregroundStyle(.secondary).frame(width: 240, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                Text("\(layer.label) — \(rows.count)").font(.subheadline).bold()
            }
        }
    }

    private func collect() {
        isRunning = true
        message = nil

        Task {
            do {
                let token = (try? WordstatCredentialStore.load()) ?? ""
                let client = WordstatClient(token: token)
                let planner = SemanticSeedPlanner.live(model: model)
                let analyzer = SemanticAgentAnalyzer.live(model: model)
                let checker = SemanticCannibalizationChecker.live(model: model)

                let runner = SemanticCollectionRunner(
                    planSeeds: { topic, masks in try await planner.plan(topic: topic, masks: masks) },
                    pullPhrases: client.provider(),
                    analyzeRelevance: { topic, queries in try await analyzer.analyze(topic: topic, queries: queries) },
                    checkCannibalization: { keywords, pages in try await checker.check(keywords: keywords, pages: pages) },
                    stopWords: stopWords.filter(\.isEnabled).map(\.text),
                    masks: masks.filter(\.isEnabled).map(\.text),
                    threshold: 10,
                    limit: 100
                )

                runID = try await runner.run(topic: topic, pages: pages, context: context)
                message = "Сбор завершён."
            } catch {
                message = error.localizedDescription
            }
            isRunning = false
        }
    }
}
```

- [ ] **Step 2: Swap the sheet and delete the dead code**

In `SemanticsEditorSheet.swift`, replace line 127:

```swift
            SemanticFunnelView(topic: topic)
```

Then delete the three obsolete files:

```bash
git rm SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift SEOContentCreator/SEOContentCreator/Logic/SemanticMockKeywordCollector.swift SEOContentCreator/SEOContentCreatorTests/SemanticMockKeywordCollectorTests.swift
```

- [ ] **Step 3: Compile and check for orphaned references**

```bash
cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `** TEST BUILD SUCCEEDED **`. Any "cannot find 'SemanticMockKeywordCollector'" means a call site was missed — fix it.

- [ ] **Step 4: Manual check**

Launch the app (Cmd+R). Open a topic, then Semantics, then the collection sheet. Run a collection. Expected: layers appear with counts, dropped queries show reasons, and survivors appear as accepted in the semantics table with frequencies.

- [ ] **Step 5: Commit**

```bash
git add -A SEOContentCreator/SEOContentCreator/Views SEOContentCreator/SEOContentCreator/Logic SEOContentCreator/SEOContentCreatorTests
git commit -m "feat: replace mock agent sheet with collection funnel screen"
```

---

### Task 13: Reference lists in Templates

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/TemplateCategory.swift:5-21`
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/SemanticReferenceEditorView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift:25,184,215`

- [ ] **Step 1: Add the category**

In `TemplateCategory.swift`, add the case and its title:

```swift
enum TemplateCategory: String, CaseIterable, Identifiable {
    case stages         // Этапы (prompt + role + context blocks merged per stage)
    case images         // Изображения (промты + пресеты)
    case skills         // Скиллы
    case forbidden      // Фразы (запрещённые формулировки + словарь правок)
    case semantics      // Семантика (минус-слова + вопросительные маски)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stages:    return "Этапы"
        case .images:    return "Изображения"
        case .skills:    return "Скиллы"
        case .forbidden: return "Фразы"
        case .semantics: return "Семантика"
        }
    }
}
```

- [ ] **Step 2: Write the editor view**

```swift
import SwiftData
import SwiftUI

/// Minus-words and question masks for the semantic collection funnel.
struct SemanticReferenceEditorView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SemanticStopWord.order) private var stopWords: [SemanticStopWord]
    @Query(sort: \SemanticQueryMask.order) private var masks: [SemanticQueryMask]

    @State private var newStopWord = ""
    @State private var newMask = ""

    var body: some View {
        HSplitView {
            stopWordColumn
            maskColumn
        }
        .padding()
    }

    private var stopWordColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Минус-слова").font(.headline)
            Text("Запрос с таким словом не попадёт в семантику ни по одной теме.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                TextField("Новое слово", text: $newStopWord)
                    .onSubmit { addStopWord() }
                Button("Добавить") { addStopWord() }
                    .disabled(newStopWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(stopWords, id: \.uuid) { word in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { word.isEnabled },
                            set: { word.isEnabled = $0; word.updatedAt = .now }
                        ))
                        .labelsHidden()
                        Text(word.text)
                        Spacer()
                        Button(role: .destructive) {
                            context.delete(word)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .frame(minWidth: 300)
    }

    private var maskColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Вопросительные маски").font(.headline)
            Text("Из этого списка агент выбирает слова для сбора информационных запросов.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                TextField("Новая маска", text: $newMask)
                    .onSubmit { addMask() }
                Button("Добавить") { addMask() }
                    .disabled(newMask.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(masks, id: \.uuid) { mask in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { mask.isEnabled },
                            set: { mask.isEnabled = $0; mask.updatedAt = .now }
                        ))
                        .labelsHidden()
                        Text(mask.text)
                        Spacer()
                        Button(role: .destructive) {
                            context.delete(mask)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .frame(minWidth: 300)
    }

    private func addStopWord() {
        let text = newStopWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        context.insert(SemanticStopWord(text: text, order: (stopWords.map(\.order).max() ?? -1) + 1))
        newStopWord = ""
    }

    private func addMask() {
        let text = newMask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        context.insert(SemanticQueryMask(text: text, order: (masks.map(\.order).max() ?? -1) + 1))
        newMask = ""
    }
}
```

- [ ] **Step 3: Wire the category into TemplatesView**

Open `TemplatesView.swift` and find the `switch category` that renders each category's body (near the top-level content, alongside the existing `.stages`, `.images`, `.skills`, `.forbidden` cases). Add:

```swift
            case .semantics: SemanticReferenceEditorView()
```

The tab strip at line 184 iterates `TemplateCategory.allCases`, so the new tab appears with no further change.

- [ ] **Step 4: Compile**

```bash
cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST BUILD SUCCEEDED **`. A "switch must be exhaustive" error means Step 3 was missed.

- [ ] **Step 5: Manual check**

Launch the app. Open Шаблоны, then the Семантика tab. Add a minus-word, then re-run collection on a topic that previously produced a query containing it. Expected: the query now appears under "Отсеяно правилами".

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/TemplateCategory.swift SEOContentCreator/SEOContentCreator/Views/Templates/SemanticReferenceEditorView.swift SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift
git commit -m "feat: add semantic reference lists to Templates"
```

---

### Task 14: Wordstat token in Settings

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/SettingsView.swift`

- [ ] **Step 1: Read the existing OpenAI key field**

```bash
grep -n "KeychainService\|SecureField\|apiKey" SEOContentCreator/SEOContentCreator/Views/SettingsView.swift
```

- [ ] **Step 2: Add a matching field for the Wordstat token**

Mirror the OpenAI key field exactly — same layout, same save button behavior, same success and failure messages — but call `WordstatCredentialStore.save(_:)` and `WordstatCredentialStore.load()`. Label it «Токен Wordstat» with the help text «Нужен для сбора семантики. Хранится в Keychain, как ключ OpenAI.»

- [ ] **Step 3: Compile and check manually**

```bash
cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5
```

Launch the app, open Настройки (Cmd+,), paste the token, save, quit, relaunch, and confirm the field still shows a saved value.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/SettingsView.swift
git commit -m "feat: add Wordstat token to settings"
```

---

### Task 15: Update project memory

**Files:**
- Modify: `ai/changelog.md`
- Modify: `ai/current-task.md`

- [ ] **Step 1: Add the changelog entry**

Add at the top of the "## Текущий changelog" section, following the existing Change/Impact/Manual checks format. State plainly which tests actually ran via Cmd+U and which did not.

- [ ] **Step 2: Mark the task ready to close**

Set `Status: review` and `Stage: review` in `ai/current-task.md`, and fill the Agent handoff section with what changed, open risks, and what to check next.

- [ ] **Step 3: Propose task-finish**

Do not close the task. Tell the user the work looks complete and propose running `task-finish`, per `ai/skills/task-finish/SKILL.md`.

- [ ] **Step 4: Commit**

```bash
git add ai/changelog.md ai/current-task.md
git commit -m "docs: record semantic auto-collection in project memory"
```

---

## Spec Coverage Check

| Spec requirement | Task |
|---|---|
| AI planner: synonyms, masks, tails | 6, 7 |
| Real Wordstat API with frequencies | 1, 10 |
| Rule layer: normalize, dedup, minus-words, threshold, top-100 | 3 |
| Cut runs after rules | 3 (`cutRunsAfterRulesSoLimitIsFilled`) |
| AI relevance layer, academic phrasing rejected | 8 |
| Long-tail 3-7 word generation | 8, 11 |
| Separate cannibalization layer | 9 |
| Funnel journal with layer and reason | 5, 11 |
| Funnel screen with per-layer counts | 12 |
| Editable minus-word and mask lists | 4, 13 |
| Reference lists reachable from Templates | 13 |
| `SemanticMockKeywordCollector` removed | 12 |
| Survivors saved as `accepted` | 11 |
| Re-run does not overwrite user decisions | 11 |
| Region and device defaults | 10 (`defaultRegions`) |
| Frequency threshold 10 | 11, 12 |
| Partial Wordstat failure tolerated | 11 |
| Empty result leaves semantics untouched | 11 (`RunError.noPhrasesPulled`) |
| Missing credentials named clearly | 10, 14 |
| Quota exceeded handled | 10 |

Out of scope in the spec and therefore absent here: clustering, SERP comparison, Topvisor import, manual Wordstat paste (already exists in `SemanticsEditorSheet`), scheduled re-collection.
