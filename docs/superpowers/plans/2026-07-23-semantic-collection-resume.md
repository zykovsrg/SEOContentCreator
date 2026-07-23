# Semantic Collection Resume + Stop-on-Wordstat-Error Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `SemanticCollectionRunner.run` stop the whole run the instant Wordstat fails (network drop, API error), and persist enough progress that a following run for the same topic resumes from the last completed seed instead of starting over — with an explicit user-triggered reset.

**Architecture:** A new one-to-one SwiftData model, `SemanticCollectionCheckpoint`, attached to `Topic`, holds the seed plan, which seeds already succeeded, the Wordstat results gathered so far, and the settings (stop-words/masks/threshold/limit) frozen at the first attempt. `SemanticCollectionRunner.run` reads this checkpoint at the start: if present, it skips AI seed planning and already-completed seeds and uses the frozen settings for filtering, regardless of what it was constructed with; if absent, it creates one right after planning succeeds. Any seed-pull error now aborts the whole run instead of being swallowed. The checkpoint is deleted on successful completion, or explicitly via a new `resetCheckpoint` helper. `SemanticFunnelView` gets a resume/reset UI built on top of this.

**Tech Stack:** Swift, SwiftData, Swift Testing (`@Test`, `#expect`, `#require`), SwiftUI.

Full design: `docs/superpowers/specs/2026-07-23-semantic-collection-resume-design.md`.

---

### Task 1: `WordstatPhrase` becomes `Codable`

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/WordstatProvider.swift`

- [ ] **Step 1: Add `Codable` conformance**

In `SEOContentCreator/SEOContentCreator/Logic/WordstatProvider.swift`, change:

```swift
struct WordstatPhrase: Equatable, Sendable {
    var text: String
    var frequency: Int
}
```

to:

```swift
struct WordstatPhrase: Codable, Equatable, Sendable {
    var text: String
    var frequency: Int
}
```

- [ ] **Step 2: Confirm the project still compiles**

Run:
```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task1.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task1.log
```
Expected: `EXIT:0` and `** TEST BUILD SUCCEEDED **` in the tail.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/WordstatProvider.swift
git commit -m "refactor: make WordstatPhrase Codable for checkpoint persistence"
```

---

### Task 2: `SemanticCollectionCheckpoint` model + wiring

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/SemanticCollectionCheckpoint.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift`

- [ ] **Step 1: Write the failing test**

In `SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift`, first update `makeContext()` to register the new model (it does not exist yet, so this alone will fail to compile):

```swift
private func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Topic.self, ReaderIntent.self, SemanticKeyword.self, SemanticFunnelEntry.self,
        SemanticCollectionCheckpoint.self,
        configurations: config
    )
    return ModelContext(container)
}
```

Then add this test right after `makeContext()` (still inside `struct SemanticCollectionRunnerTests`):

```swift
@Test func checkpointPersistsOnATopicAndReadsBack() throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    let checkpoint = SemanticCollectionCheckpoint(
        runID: UUID(),
        seeds: ["рак груди", "рак груди лечение"],
        stopWords: ["реферат"],
        masks: ["как"],
        threshold: 10,
        limit: 100
    )
    checkpoint.topic = topic
    context.insert(checkpoint)
    try context.save()

    #expect(topic.collectionCheckpoint === checkpoint)
    #expect(checkpoint.seeds == ["рак груди", "рак груди лечение"])
    #expect(checkpoint.completedSeeds.isEmpty)
    #expect(checkpoint.pulled.isEmpty)
    #expect(checkpoint.stopWordsSnapshot == ["реферат"])
    #expect(checkpoint.masksSnapshot == ["как"])
    #expect(checkpoint.thresholdSnapshot == 10)
    #expect(checkpoint.limitSnapshot == 100)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task2-red.log 2>&1; echo "EXIT:$?"; tail -20 /tmp/plan-task2-red.log
```
Expected: compile error — `cannot find type 'SemanticCollectionCheckpoint' in scope`.

- [ ] **Step 3: Create the model**

Create `SEOContentCreator/SEOContentCreator/Models/SemanticCollectionCheckpoint.swift`:

```swift
import Foundation
import SwiftData

/// Resumable progress for one in-flight `SemanticCollectionRunner.run` call.
/// One per `Topic`. Deleted when the run finishes successfully, or explicitly
/// via `SemanticCollectionRunner.resetCheckpoint`.
@Model
final class SemanticCollectionCheckpoint {
    var uuid: UUID
    var runID: UUID
    /// Full seed-phrase plan, computed once by the AI planner and never
    /// recomputed while this checkpoint exists.
    var seeds: [String]
    /// Seeds already pulled from Wordstat successfully.
    var completedSeeds: [String]
    /// Wordstat results accumulated so far, across every completed seed.
    var pulled: [WordstatPhrase]
    /// Settings frozen at the first attempt; later edits to stop-words/masks/
    /// threshold/limit only apply to a fresh run, not a resumed one.
    var stopWordsSnapshot: [String]
    var masksSnapshot: [String]
    var thresholdSnapshot: Int
    var limitSnapshot: Int
    var createdAt: Date
    var updatedAt: Date

    var topic: Topic?

    init(
        runID: UUID,
        seeds: [String],
        stopWords: [String],
        masks: [String],
        threshold: Int,
        limit: Int
    ) {
        self.uuid = UUID()
        self.runID = runID
        self.seeds = seeds
        self.completedSeeds = []
        self.pulled = []
        self.stopWordsSnapshot = stopWords
        self.masksSnapshot = masks
        self.thresholdSnapshot = threshold
        self.limitSnapshot = limit
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

- [ ] **Step 4: Wire the relationship into `Topic`**

In `SEOContentCreator/SEOContentCreator/Models/Topic.swift`, add this relationship right after `readerIntent` (around line 46):

```swift
    @Relationship(deleteRule: .cascade, inverse: \ReaderIntent.topic)
    var readerIntent: ReaderIntent?
    @Relationship(deleteRule: .cascade, inverse: \SemanticCollectionCheckpoint.topic)
    var collectionCheckpoint: SemanticCollectionCheckpoint?
```

No change needed to `Topic.init` — this is an optional relationship, same as `readerIntent`.

- [ ] **Step 5: Register the model in the app's `ModelContainer`**

In `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`, change:

```swift
        .modelContainer(for: [
            Topic.self, ReaderIntent.self, KnowledgeNode.self,
            ArticleVersion.self, GenerationJob.self, StageTemplate.self,
            ContextBlock.self, AIRole.self,
            GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
            ExternalDocument.self, EditorDictionary.self, SkillPreset.self,
            SemanticKeyword.self, PublishedSitePage.self,
            ProductBlock.self, ForbiddenPhrase.self,
            PersistedRemark.self, PromptRecommendation.self,
            SemanticStopWord.self, SemanticQueryMask.self, SemanticFunnelEntry.self
        ])
```

to:

```swift
        .modelContainer(for: [
            Topic.self, ReaderIntent.self, KnowledgeNode.self,
            ArticleVersion.self, GenerationJob.self, StageTemplate.self,
            ContextBlock.self, AIRole.self,
            GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
            ExternalDocument.self, EditorDictionary.self, SkillPreset.self,
            SemanticKeyword.self, PublishedSitePage.self,
            ProductBlock.self, ForbiddenPhrase.self,
            PersistedRemark.self, PromptRecommendation.self,
            SemanticStopWord.self, SemanticQueryMask.self, SemanticFunnelEntry.self,
            SemanticCollectionCheckpoint.self
        ])
```

- [ ] **Step 6: Run test to verify it passes**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task2-green-build.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task2-green-build.log
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/checkpointPersistsOnATopicAndReadsBack" > /tmp/plan-task2-green-test.log 2>&1; echo "EXIT:$?"; tail -20 /tmp/plan-task2-green-test.log
```
Expected: both `EXIT:0`; test log shows `checkpointPersistsOnATopicAndReadsBack() passed`.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/SemanticCollectionCheckpoint.swift \
        SEOContentCreator/SEOContentCreator/Models/Topic.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift \
        SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift
git commit -m "feat: add SemanticCollectionCheckpoint model"
```

---

### Task 3: `resetCheckpoint` helper

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `SemanticCollectionRunnerTests.swift`:

```swift
@Test func resetCheckpointDeletesIt() throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    let checkpoint = SemanticCollectionCheckpoint(
        runID: UUID(), seeds: ["старый"],
        stopWords: [], masks: [], threshold: 10, limit: 100
    )
    checkpoint.topic = topic
    context.insert(checkpoint)
    try context.save()
    #expect(topic.collectionCheckpoint != nil)

    try SemanticCollectionRunner.resetCheckpoint(for: topic, context: context)

    #expect(topic.collectionCheckpoint == nil)
}

@Test func resetCheckpointIsANoOpWhenThereIsNoCheckpoint() throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    try SemanticCollectionRunner.resetCheckpoint(for: topic, context: context)

    #expect(topic.collectionCheckpoint == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task3-red.log 2>&1; echo "EXIT:$?"; tail -20 /tmp/plan-task3-red.log
```
Expected: compile error — `type 'SemanticCollectionRunner' has no member 'resetCheckpoint'`.

- [ ] **Step 3: Implement the helper**

In `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift`, add this extension at the very end of the file (after the closing brace of `SemanticMergeRollback`):

```swift
extension SemanticCollectionRunner {
    /// Discards saved progress for a topic so the next run starts from zero.
    /// Does not touch the funnel journal or semantic keywords.
    static func resetCheckpoint(for topic: Topic, context: ModelContext) throws {
        guard let checkpoint = topic.collectionCheckpoint else { return }
        context.delete(checkpoint)
        try context.save()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task3-green-build.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task3-green-build.log
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/resetCheckpointDeletesIt" -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/resetCheckpointIsANoOpWhenThereIsNoCheckpoint" > /tmp/plan-task3-green-test.log 2>&1; echo "EXIT:$?"; tail -20 /tmp/plan-task3-green-test.log
```
Expected: both `EXIT:0`; both tests `passed`.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift \
        SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift
git commit -m "feat: add SemanticCollectionRunner.resetCheckpoint"
```

---

### Task 4: Stop the whole run on any Wordstat seed error

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift`

This task changes the seed loop's error handling only. Checkpoint creation/resume
is added in Task 5 — for now, the loop just needs to stop instead of continuing.

- [ ] **Step 1: Replace the existing test that expects the run to continue past a failed seed**

In `SemanticCollectionRunnerTests.swift`, find `recordsRealErrorMessageWhenASeedFails` and replace the whole test with:

```swift
@Test func stopsTheRunImmediatelyWhenASeedFails() async throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    struct FakePullError: Error, LocalizedError {
        var errorDescription: String? { "квота исчерпана" }
    }

    var attemptedSeeds: [String] = []
    let runner = SemanticCollectionRunner(
        planSeeds: { _, _ in SemanticSeedPlan(synonyms: ["первый", "второй", "третий"], masks: [], tails: []) },
        pullPhrases: { seed in
            attemptedSeeds.append(seed)
            if seed == "второй" { throw FakePullError() }
            return [WordstatPhrase(text: "\(seed) запрос", frequency: 500)]
        },
        analyzeRelevance: { _, _ in SemanticAgentAnalysis(keywords: [], longTail: []) },
        checkCannibalization: { keywords, _ in keywords },
        stopWords: [],
        masks: [],
        threshold: 10,
        limit: 100
    )

    await #expect(throws: FakePullError.self) {
        try await runner.run(topic: topic, pages: [], context: context)
    }

    #expect(attemptedSeeds == ["первый", "второй"])
    let failedSeed = topic.funnelEntries.first { $0.text == "второй" }
    #expect(failedSeed?.reason == "квота исчерпана")
    #expect(topic.semanticKeywords.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task4-red-build.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task4-red-build.log
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/stopsTheRunImmediatelyWhenASeedFails" > /tmp/plan-task4-red-test.log 2>&1; echo "EXIT:$?"; tail -30 /tmp/plan-task4-red-test.log
```
Expected: build passes, but the test **fails** — `attemptedSeeds` will be
`["первый", "второй", "третий"]` (the current code keeps going) and no error is thrown.

- [ ] **Step 3: Change the seed loop to stop on error**

In `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift`, replace:

```swift
        var pulled: [WordstatPhrase] = []
        let seeds = plan.seedPhrases()
        reportProgress(.wordstat(completed: 0, total: seeds.count))
        for (index, seed) in seeds.enumerated() {
            try Task.checkCancellation()
            // A failing seed must not abort the run; the funnel records why it failed.
            do {
                let phrases = try await pullPhrases(seed)
                try Task.checkCancellation()
                pulled.append(contentsOf: phrases)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                record(topic: topic, context: context, text: seed, frequency: nil,
                       layer: .raw, reason: error.localizedDescription, runID: runID)
            }
            reportProgress(.wordstat(completed: index + 1, total: seeds.count))
        }
```

with:

```swift
        var pulled: [WordstatPhrase] = []
        let seeds = plan.seedPhrases()
        var completedSeeds = 0
        reportProgress(.wordstat(completed: 0, total: seeds.count))
        for seed in seeds {
            try Task.checkCancellation()
            do {
                let phrases = try await pullPhrases(seed)
                try Task.checkCancellation()
                pulled.append(contentsOf: phrases)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Every pullPhrases error means Wordstat itself failed to
                // answer (network, auth, quota, unparseable response) — a
                // legitimately empty result returns [], never throws. So any
                // error here means continuing to the next seed would just
                // burn through an already-unreachable API. Record it for
                // visibility, then stop the whole run.
                record(topic: topic, context: context, text: seed, frequency: nil,
                       layer: .raw, reason: error.localizedDescription, runID: runID)
                throw error
            }
            completedSeeds += 1
            reportProgress(.wordstat(completed: completedSeeds, total: seeds.count))
        }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task4-green-build.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task4-green-build.log
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/stopsTheRunImmediatelyWhenASeedFails" > /tmp/plan-task4-green-test.log 2>&1; echo "EXIT:$?"; tail -20 /tmp/plan-task4-green-test.log
```
Expected: both `EXIT:0`; test `passed`.

- [ ] **Step 5: Run the full test class to check for regressions from this behavior change**

```bash
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests" > /tmp/plan-task4-full.log 2>&1; echo "EXIT:$?"; tail -40 /tmp/plan-task4-full.log
```
Expected: `EXIT:0`, all tests `passed`. (`recordsRealErrorMessageWhenASeedFails`
no longer exists — it was replaced in Step 1.)

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift \
        SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift
git commit -m "fix: stop semantic collection run on any Wordstat seed error"
```

---

### Task 5: Checkpoint creation, resume, and cleanup in `run()`

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `SemanticCollectionRunnerTests.swift`:

```swift
@Test func failingSeedLeavesACheckpointWithProgressSoFar() async throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    struct FakeWordstatError: Error, LocalizedError {
        var errorDescription: String? { "Wordstat недоступен" }
    }

    let runner = SemanticCollectionRunner(
        planSeeds: { _, _ in SemanticSeedPlan(synonyms: ["первый", "второй", "третий"], masks: [], tails: []) },
        pullPhrases: { seed in
            if seed == "второй" { throw FakeWordstatError() }
            return [WordstatPhrase(text: "\(seed) запрос", frequency: 500)]
        },
        analyzeRelevance: { _, _ in SemanticAgentAnalysis(keywords: [], longTail: []) },
        checkCannibalization: { keywords, _ in keywords },
        stopWords: ["минус"],
        masks: [],
        threshold: 10,
        limit: 100
    )

    await #expect(throws: FakeWordstatError.self) {
        try await runner.run(topic: topic, pages: [], context: context)
    }

    let checkpoint = try #require(topic.collectionCheckpoint)
    #expect(checkpoint.seeds == ["первый", "второй", "третий"])
    #expect(checkpoint.completedSeeds == ["первый"])
    #expect(checkpoint.pulled.map(\.text) == ["первый запрос"])
    #expect(checkpoint.stopWordsSnapshot == ["минус"])
    #expect(checkpoint.thresholdSnapshot == 10)
    #expect(checkpoint.limitSnapshot == 100)
}

@Test func resumingSkipsSeedsAlreadyInTheCheckpointAndDoesNotReplan() async throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    let checkpoint = SemanticCollectionCheckpoint(
        runID: UUID(), seeds: ["первый", "второй"],
        stopWords: [], masks: [], threshold: 10, limit: 100
    )
    checkpoint.completedSeeds = ["первый"]
    checkpoint.pulled = [WordstatPhrase(text: "первый запрос", frequency: 500)]
    checkpoint.topic = topic
    context.insert(checkpoint)
    try context.save()

    var attemptedSeeds: [String] = []
    let runner = SemanticCollectionRunner(
        planSeeds: { _, _ in
            Issue.record("planSeeds must not be called when a checkpoint already exists")
            return SemanticSeedPlan(synonyms: [], masks: [], tails: [])
        },
        pullPhrases: { seed in
            attemptedSeeds.append(seed)
            return [WordstatPhrase(text: "второй запрос", frequency: 300)]
        },
        analyzeRelevance: { _, queries in
            SemanticAgentAnalysis(
                keywords: queries.map {
                    SemanticAgentKeywordResult(
                        query: $0.text, frequency: nil, recommendation: .include, reasonCategory: .none,
                        explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
                    )
                },
                longTail: []
            )
        },
        checkCannibalization: { keywords, _ in keywords },
        stopWords: [],
        masks: [],
        threshold: 10,
        limit: 100
    )

    try await runner.run(topic: topic, pages: [], context: context)

    #expect(attemptedSeeds == ["второй"])
    #expect(topic.semanticKeywords.map(\.text).sorted() == ["второй запрос", "первый запрос"])
}

@Test func resumedRunUsesSettingsFrozenAtFirstAttemptNotTheRunnersConstructorValues() async throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    // Frozen at the first attempt: no stop-words.
    let checkpoint = SemanticCollectionCheckpoint(
        runID: UUID(), seeds: ["рак груди реферат"],
        stopWords: [], masks: [], threshold: 10, limit: 100
    )
    checkpoint.topic = topic
    context.insert(checkpoint)
    try context.save()

    let runner = SemanticCollectionRunner(
        planSeeds: { _, _ in
            Issue.record("planSeeds must not be called when a checkpoint already exists")
            return SemanticSeedPlan(synonyms: [], masks: [], tails: [])
        },
        pullPhrases: { _ in [WordstatPhrase(text: "рак груди реферат", frequency: 900)] },
        analyzeRelevance: { _, queries in
            SemanticAgentAnalysis(
                keywords: queries.map {
                    SemanticAgentKeywordResult(
                        query: $0.text, frequency: nil, recommendation: .include, reasonCategory: .none,
                        explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
                    )
                },
                longTail: []
            )
        },
        checkCannibalization: { keywords, _ in keywords },
        // Live setting now has a stop-word that would drop this phrase — but
        // the checkpoint's frozen (empty) snapshot must win.
        stopWords: ["реферат"],
        masks: [],
        threshold: 10,
        limit: 100
    )

    try await runner.run(topic: topic, pages: [], context: context)

    #expect(topic.semanticKeywords.map(\.text) == ["рак груди реферат"])
}

@Test func successfulRunDeletesTheCheckpoint() async throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    let runner = makeRunner(
        pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
        analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
    )

    try await runner.run(topic: topic, pages: [], context: context)

    #expect(topic.collectionCheckpoint == nil)
}

@Test func resetCheckpointClearsProgressSoTheNextRunStartsFresh() async throws {
    let context = try makeContext()
    let topic = Topic(title: "Рак груди", articleType: .disease)
    context.insert(topic)

    let oldCheckpoint = SemanticCollectionCheckpoint(
        runID: UUID(), seeds: ["старый"],
        stopWords: [], masks: [], threshold: 10, limit: 100
    )
    oldCheckpoint.completedSeeds = ["старый"]
    oldCheckpoint.pulled = [WordstatPhrase(text: "старый запрос", frequency: 500)]
    oldCheckpoint.topic = topic
    context.insert(oldCheckpoint)
    try context.save()

    try SemanticCollectionRunner.resetCheckpoint(for: topic, context: context)
    #expect(topic.collectionCheckpoint == nil)

    var plannedSeeds: [String] = []
    let runner = SemanticCollectionRunner(
        planSeeds: { _, _ in
            SemanticSeedPlan(synonyms: ["новый"], masks: [], tails: [])
        },
        pullPhrases: { seed in
            plannedSeeds.append(seed)
            return [WordstatPhrase(text: "новый запрос", frequency: 500)]
        },
        analyzeRelevance: { _, queries in
            SemanticAgentAnalysis(
                keywords: queries.map {
                    SemanticAgentKeywordResult(
                        query: $0.text, frequency: nil, recommendation: .include, reasonCategory: .none,
                        explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
                    )
                },
                longTail: []
            )
        },
        checkCannibalization: { keywords, _ in keywords },
        stopWords: [],
        masks: [],
        threshold: 10,
        limit: 100
    )

    try await runner.run(topic: topic, pages: [], context: context)

    #expect(plannedSeeds == ["новый"])
    #expect(topic.collectionCheckpoint == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task5-red-build.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task5-red-build.log
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/failingSeedLeavesACheckpointWithProgressSoFar" \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/resumingSkipsSeedsAlreadyInTheCheckpointAndDoesNotReplan" \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/resumedRunUsesSettingsFrozenAtFirstAttemptNotTheRunnersConstructorValues" \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/successfulRunDeletesTheCheckpoint" \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/resetCheckpointClearsProgressSoTheNextRunStartsFresh" \
  > /tmp/plan-task5-red-test.log 2>&1; echo "EXIT:$?"; tail -60 /tmp/plan-task5-red-test.log
```
Expected: build succeeds, but tests fail — no checkpoint is created yet
(`topic.collectionCheckpoint` is `nil` where a checkpoint is expected), and
`resumingSkipsSeedsAlreadyInTheCheckpointAndDoesNotReplan` fails because
`planSeeds` still gets called (`Issue.record` fires) since resume logic
doesn't exist yet.

- [ ] **Step 3: Implement checkpoint creation, resume, and cleanup**

In `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift`,
replace the whole `run` function body from its signature down through the
seed loop (i.e. everything from `func run(...)` through the closing `}` of the
`for seed in seeds { ... }` loop added in Task 4) with:

```swift
    @discardableResult
    func run(topic: Topic, pages: [PublishedSitePage], context: ModelContext) async throws -> UUID {
        try Task.checkCancellation()

        let checkpoint: SemanticCollectionCheckpoint
        let runID: UUID
        let seeds: [String]
        var pulled: [WordstatPhrase]
        var completedSeeds: Set<String>

        if let existing = topic.collectionCheckpoint {
            checkpoint = existing
            runID = existing.runID
            seeds = existing.seeds
            pulled = existing.pulled
            completedSeeds = Set(existing.completedSeeds)
            reportProgress(.wordstat(completed: completedSeeds.count, total: seeds.count))
        } else {
            runID = UUID()
            reportProgress(.planning)
            try Task.checkCancellation()
            let plan = try await planSeeds(topic, masks)
            try Task.checkCancellation()
            seeds = plan.seedPhrases()
            pulled = []
            completedSeeds = []
            let created = SemanticCollectionCheckpoint(
                runID: runID, seeds: seeds,
                stopWords: stopWords, masks: masks, threshold: threshold, limit: limit
            )
            created.topic = topic
            context.insert(created)
            try saveContext(context)
            checkpoint = created
            reportProgress(.wordstat(completed: 0, total: seeds.count))
        }

        // A resumed run always uses the settings frozen when the checkpoint
        // was first created, even if this runner was constructed with
        // different live settings.
        let effectiveStopWords = checkpoint.stopWordsSnapshot
        let effectiveThreshold = checkpoint.thresholdSnapshot
        let effectiveLimit = checkpoint.limitSnapshot

        for seed in seeds {
            try Task.checkCancellation()
            guard !completedSeeds.contains(seed) else { continue }
            do {
                let phrases = try await pullPhrases(seed)
                try Task.checkCancellation()
                pulled.append(contentsOf: phrases)
                completedSeeds.insert(seed)
                checkpoint.pulled = pulled
                checkpoint.completedSeeds = Array(completedSeeds)
                checkpoint.updatedAt = .now
                try saveContext(context)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Every pullPhrases error means Wordstat itself failed to
                // answer (network, auth, quota, unparseable response) — a
                // legitimately empty result returns [], never throws. So any
                // error here means continuing to the next seed would just
                // burn through an already-unreachable API. Record it for
                // visibility, then stop the whole run. The checkpoint keeps
                // whatever progress was made so far.
                record(topic: topic, context: context, text: seed, frequency: nil,
                       layer: .raw, reason: error.localizedDescription, runID: runID)
                try saveContext(context)
                throw error
            }
            reportProgress(.wordstat(completed: completedSeeds.count, total: seeds.count))
        }
```

Then, further down in the same function, change:

```swift
        let filtered = SemanticRuleFilter.apply(pulled, stopWords: stopWords, threshold: threshold, limit: limit)
```

to:

```swift
        let filtered = SemanticRuleFilter.apply(pulled, stopWords: effectiveStopWords, threshold: effectiveThreshold, limit: effectiveLimit)
```

Finally, change the closing save block from:

```swift
        let rollback = SemanticMergeRollback.capture(topic: topic)
        do {
            reportProgress(.saving)
            try Task.checkCancellation()
            SemanticKeywordMerger.merge(survivors, into: topic, decision: .accepted)
            if let intent = topic.readerIntent {
                intent.semanticSnapshot = ReaderIntent.acceptedSemanticSnapshot(for: topic)
                intent.updatedAt = .now
            }
            try saveContext(context)
        } catch {
            rollback.restore(topic: topic, context: context)
            throw error
        }

        return runID
    }
```

to:

```swift
        let rollback = SemanticMergeRollback.capture(topic: topic)
        do {
            reportProgress(.saving)
            try Task.checkCancellation()
            SemanticKeywordMerger.merge(survivors, into: topic, decision: .accepted)
            if let intent = topic.readerIntent {
                intent.semanticSnapshot = ReaderIntent.acceptedSemanticSnapshot(for: topic)
                intent.updatedAt = .now
            }
            context.delete(checkpoint)
            try saveContext(context)
        } catch {
            rollback.restore(topic: topic, context: context)
            throw error
        }

        return runID
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task5-green-build.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task5-green-build.log
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/failingSeedLeavesACheckpointWithProgressSoFar" \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/resumingSkipsSeedsAlreadyInTheCheckpointAndDoesNotReplan" \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/resumedRunUsesSettingsFrozenAtFirstAttemptNotTheRunnersConstructorValues" \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/successfulRunDeletesTheCheckpoint" \
  -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests/resetCheckpointClearsProgressSoTheNextRunStartsFresh" \
  > /tmp/plan-task5-green-test.log 2>&1; echo "EXIT:$?"; tail -60 /tmp/plan-task5-green-test.log
```
Expected: both `EXIT:0`; all five tests `passed`.

- [ ] **Step 5: Run the full test class**

```bash
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:"SEOContentCreatorTests/SemanticCollectionRunnerTests" > /tmp/plan-task5-full.log 2>&1; echo "EXIT:$?"; tail -60 /tmp/plan-task5-full.log
```
Expected: `EXIT:0`, every test `passed` (this now includes the large-journal
regression test from the crash fix — expect it to take a few minutes; that is
normal and matches prior runs).

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift \
        SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift
git commit -m "feat: resume interrupted semantic collection from a saved checkpoint"
```

---

### Task 6: `SemanticFunnelView` resume/reset UI

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/SemanticFunnelView.swift`

No automated test for this task — it is a SwiftUI view. Verify manually per
Step 5 below (this project's `ui-review` convention for decorative/interactive
UI changes without new business logic).

- [ ] **Step 1: Add reset-confirmation state**

In `SemanticFunnelView`, change:

```swift
    @State private var collectionTask: Task<Void, Never>?
    @State private var stopRequested = false
```

to:

```swift
    @State private var collectionTask: Task<Void, Never>?
    @State private var stopRequested = false
    @State private var showResetConfirmation = false
```

- [ ] **Step 2: Change the button row to show resume/reset state**

Change:

```swift
            HStack {
                Button(isRunning ? "Собираю…" : "Собрать семантику") { collect() }
                    .disabled(isRunning)
                    .keyboardShortcut(.defaultAction)
                if isRunning {
                    Button("Остановить", role: .destructive) { stopCollection() }
                }
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
            }

            if isRunning, let startedAt {
```

to:

```swift
            HStack {
                Button(collectButtonLabel) { collect() }
                    .disabled(isRunning)
                    .keyboardShortcut(.defaultAction)
                if isRunning {
                    Button("Остановить", role: .destructive) { stopCollection() }
                } else if topic.collectionCheckpoint != nil {
                    Button("Сбросить") { showResetConfirmation = true }
                }
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
            }

            if !isRunning, let checkpoint = topic.collectionCheckpoint {
                Text("Прошлый сбор остановлен: \(checkpoint.completedSeeds.count) из \(checkpoint.seeds.count) запросов получено.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isRunning, let startedAt {
```

- [ ] **Step 3: Add the `collectButtonLabel` helper and `resetProgress` action**

Add this computed property right above `private func collect()`:

```swift
    private var collectButtonLabel: String {
        if isRunning { return "Собираю…" }
        return topic.collectionCheckpoint != nil ? "Продолжить сбор" : "Собрать семантику"
    }

    private func resetProgress() {
        try? SemanticCollectionRunner.resetCheckpoint(for: topic, context: context)
    }
```

- [ ] **Step 4: Add the confirmation dialog and distinguish the auto-stop message**

Change the catch block in `collect()` from:

```swift
            } catch {
                if let runError = error as? SemanticCollectionRunner.RunError {
                    runID = runError.runID
                }
                message = error.localizedDescription
            }
```

to:

```swift
            } catch {
                if let runError = error as? SemanticCollectionRunner.RunError {
                    runID = runError.runID
                }
                if topic.collectionCheckpoint != nil {
                    message = "\(error.localizedDescription)\nПрогресс сохранён, можно продолжить позже."
                } else {
                    message = error.localizedDescription
                }
            }
```

Then add a confirmation dialog modifier right after the existing `.onDisappear` block
at the bottom of `body`:

```swift
        .onDisappear {
            collectionTask?.cancel()
        }
        .confirmationDialog(
            "Сбросить сохранённый прогресс сбора?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) { resetProgress() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Весь прогресс текущего незавершённого сбора будет потерян.")
        }
    }
```

(This replaces the final two closing lines of `body` — the modifier attaches
to the outer `VStack`, so it goes after `.onDisappear` and before the closing
brace of `var body`.)

- [ ] **Step 5: Build and manually verify in the app**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild -scheme SEOContentCreator -configuration Debug build > /tmp/plan-task6-build.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task6-build.log
```
Expected: `EXIT:0`, `** BUILD SUCCEEDED **`.

Then run the app (Cmd+R in Xcode, or launch the built `.app` from
DerivedData) and manually confirm:
- Starting a fresh collection with no checkpoint shows "Собрать семантику".
- Clicking "Остановить" mid-run, then reopening the funnel screen, shows
  "Продолжить сбор" and a "Сбросить" button, plus the progress line.
- Clicking "Продолжить сбор" continues without re-planning seeds (no new AI
  planning call — visible as the progress bar starting from where it left
  off instead of at "Планирую запросы с ИИ…").
- Clicking "Сбросить" shows the confirmation dialog; confirming returns the
  button to "Собрать семантику" and a fresh run starts from zero.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/SemanticFunnelView.swift
git commit -m "feat: resume/reset UI for interrupted semantic collection"
```

---

### Task 7: Full regression pass and task-finish

**Files:** none (verification only)

- [ ] **Step 1: Run the full test target**

```bash
cd /Users/zykovsrg/Documents/vibecode/SEOContentCreator/SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' > /tmp/plan-task7-build.log 2>&1; echo "EXIT:$?"; tail -5 /tmp/plan-task7-build.log
xcodebuild test-without-building -scheme SEOContentCreator -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:"SEOContentCreatorTests" > /tmp/plan-task7-test.log 2>&1; echo "EXIT:$?"; tail -80 /tmp/plan-task7-test.log
```
Expected: both `EXIT:0`, no failures.

- [ ] **Step 2: Report to the user**

Summarize: what changed, that all automated tests pass, and that the manual
resume/reset check from Task 6 Step 5 was (or was not) performed live in the
app — then propose `task-finish` per `ai/skills/task-finish/SKILL.md`
(changelog entry, `ai/current-task.md` cleanup, commit + push).
