# Reader Intent and Personal Prompt Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a structured, editable reader-intent card that guides only the relevant article stages, and make every explicit prompt-editor save establish a protected full personal default.

**Architecture:** Persist reader intent in a dedicated one-to-one SwiftData model and isolate AI parsing, rendering, editor state, prompt migration, and prompt-default snapshots in focused units. Upgrade stored prompts additively and idempotently, then capture the upgraded live state as the first personal default instead of replacing modified prompts with factory text.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, existing `OpenAIClient`/`StageExecutor.StreamProvider`, macOS app target with file-system-synchronized Xcode groups.

## Global Constraints

- Keep all user-facing copy in Russian.
- Do not add external dependencies or a real Wordstat/DataForSEO keyword collector.
- Use only accepted and required semantic queries as intent evidence.
- A missing or stale reader-intent card must warn but must not block any pipeline stage.
- Pass `{{задача_читателя}}` only to Structure, Draft, Semantics-in-text, and SEO-check.
- Modify the current repository prompt wording; never restore older prompt versions.
- Existing modified stored prompts must be upgraded additively and must not be replaced wholesale.
- Future factory-default updates must not overwrite live values or personal-default snapshots.
- OpenAI generation and all persistence remain explicit user actions.
- Preserve shared-role and shared-context-block semantics across stages.
- Use TDD for every behavior change and keep unrelated refactoring out of scope.
- Before Task 6, read `ai/skills/ui-review/SKILL.md` and `ai/skills/write-tests/SKILL.md` completely and apply their UI, accessibility, and test checklists.

---

## File Map

### New production files

- `SEOContentCreator/SEOContentCreator/Models/ReaderIntent.swift` — persisted model, enums, formula, semantic normalization/staleness.
- `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentDraft.swift` — non-persisted editor/AI value and apply operation.
- `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentPromptRenderer.swift` — compact prompt representation.
- `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentResponseParser.swift` — strict JSON decoding.
- `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentAnalyzer.swift` — OpenAI request and stream collection.
- `SEOContentCreator/SEOContentCreator/Logic/PromptPersonalDefaultsService.swift` — capture, save, and restore state.
- `SEOContentCreator/SEOContentCreator/Logic/StagePromptIntentMigration.swift` — idempotent v9 prompt upgrade.
- `SEOContentCreator/SEOContentCreator/Views/ReaderIntentSheet.swift` — draft editor and explicit AI generation.

### New test files

- `SEOContentCreator/SEOContentCreatorTests/ReaderIntentTests.swift`
- `SEOContentCreator/SEOContentCreatorTests/ReaderIntentAnalysisTests.swift`
- `SEOContentCreator/SEOContentCreatorTests/PromptPersonalDefaultsTests.swift`
- `SEOContentCreator/SEOContentCreatorTests/StagePromptIntentMigrationTests.swift`

The Xcode project uses file-system-synchronized groups, so new Swift files do not require manual `project.pbxproj` entries.

---

### Task 1: Persist the reader-intent domain model

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/ReaderIntent.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/ReaderIntentTests.swift`
- Modify: every test container listed in Step 4.

**Interfaces:**
- Produces: `ReaderIntent`, `ReaderIntentSolutionType`, `ReaderIntentCoverage`, `ReaderIntentSource`.
- Produces: `ReaderIntent.acceptedSemanticSnapshot(for:) -> [String]` and `ReaderIntent.isStale(for:) -> Bool`.
- Produces: optional `Topic.readerIntent: ReaderIntent?` with cascade delete.

- [ ] **Step 1: Write failing persistence and normalization tests**

```swift
import SwiftData
import Testing
@testable import SEOContentCreator

struct ReaderIntentTests {
    @Test func topicPersistsOptionalReaderIntent() throws {
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, KnowledgeNode.self, SemanticKeyword.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let intent = ReaderIntent(
            query: "рак простаты лечение",
            audienceContext: "Пациент после постановки диагноза",
            hiddenGoal: "Понять, какие варианты лечения обсудить с врачом",
            successCriterion: "Различает основные методы и ограничения",
            barriers: "Тревога и противоречивые советы",
            solutionType: .mixed,
            solutionFormat: "Сравнение + алгоритм",
            coverage: [.definition, .choiceComparison, .risksLimitations, .practicalSolution],
            source: .manual,
            semanticSnapshot: ["рак простаты лечение"]
        )
        context.insert(topic)
        context.insert(intent)
        topic.readerIntent = intent
        try context.save()
        #expect(topic.readerIntent?.hiddenGoal == "Понять, какие варианты лечения обсудить с врачом")
        #expect(intent.topic === topic)
    }

    @Test func oldTopicWithoutIntentRemainsValid() {
        #expect(Topic(title: "Тема", articleType: .info).readerIntent == nil)
    }

    @Test func snapshotUsesOnlyAcceptedAndRequiredQueries() {
        let topic = Topic(title: "Тема", articleType: .info)
        topic.semanticKeywords = [
            SemanticKeyword(text: "  Бета  ", userDecision: .required),
            SemanticKeyword(text: "альфа", userDecision: .accepted),
            SemanticKeyword(text: "мусор", userDecision: .rejected)
        ]
        #expect(ReaderIntent.acceptedSemanticSnapshot(for: topic) == ["альфа", "бета"])
    }

    @Test func intentBecomesStaleAfterAcceptedSemanticsChange() {
        let topic = Topic(title: "Тема", articleType: .info)
        topic.semanticKeywords = [SemanticKeyword(text: "первый", userDecision: .accepted)]
        let intent = ReaderIntent(query: "первый", hiddenGoal: "Получить ответ")
        intent.semanticSnapshot = ["первый"]
        #expect(intent.isStale(for: topic) == false)
        topic.semanticKeywords.append(SemanticKeyword(text: "второй", userDecision: .required))
        #expect(intent.isStale(for: topic) == true)
    }
}
```

- [ ] **Step 2: Run and verify compile failure**

Run from `SEOContentCreator/`:

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ReaderIntentTests -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: compile failure because `ReaderIntent` and `Topic.readerIntent` do not exist.

- [ ] **Step 3: Implement the model and typed accessors**

Create this exact public shape and fill every initializer assignment:

```swift
import Foundation
import SwiftData

enum ReaderIntentSolutionType: String, Codable, CaseIterable, Identifiable {
    case explanation, algorithm, comparison, directOffer, mixed
    var id: String { rawValue }
}

enum ReaderIntentCoverage: String, Codable, CaseIterable, Identifiable {
    case definition, currentRelevance, choiceComparison, evidence
    case socialProof, applicationContext, risksLimitations, practicalSolution
    var id: String { rawValue }
}

enum ReaderIntentSource: String, Codable { case manual, ai }

@Model
final class ReaderIntent {
    var uuid: UUID
    var query: String
    var audienceContext: String
    var hiddenGoal: String
    var successCriterion: String
    var barriers: String
    var solutionTypeRaw: String
    var solutionFormat: String
    var coverageRaw: [String]
    var sourceRaw: String
    var semanticSnapshot: [String]
    var createdAt: Date
    var updatedAt: Date
    var topic: Topic?

    init(
        query: String,
        audienceContext: String = "",
        hiddenGoal: String,
        successCriterion: String = "",
        barriers: String = "",
        solutionType: ReaderIntentSolutionType = .explanation,
        solutionFormat: String = "",
        coverage: Set<ReaderIntentCoverage> = [],
        source: ReaderIntentSource = .manual,
        semanticSnapshot: [String] = []
    ) {
        self.uuid = UUID()
        self.query = query
        self.audienceContext = audienceContext
        self.hiddenGoal = hiddenGoal
        self.successCriterion = successCriterion
        self.barriers = barriers
        self.solutionTypeRaw = solutionType.rawValue
        self.solutionFormat = solutionFormat
        self.coverageRaw = coverage.map(\.rawValue).sorted()
        self.sourceRaw = source.rawValue
        self.semanticSnapshot = Self.normalize(semanticSnapshot)
        self.createdAt = .now
        self.updatedAt = .now
    }

    var solutionType: ReaderIntentSolutionType {
        get { ReaderIntentSolutionType(rawValue: solutionTypeRaw) ?? .explanation }
        set { solutionTypeRaw = newValue.rawValue; updatedAt = .now }
    }

    var coverage: Set<ReaderIntentCoverage> {
        get { Set(coverageRaw.compactMap(ReaderIntentCoverage.init(rawValue:))) }
        set { coverageRaw = newValue.map(\.rawValue).sorted(); updatedAt = .now }
    }

    var source: ReaderIntentSource {
        get { ReaderIntentSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue; updatedAt = .now }
    }

    var taskFormula: String {
        let audience = Self.clean(audienceContext)
        let goal = Self.clean(hiddenGoal)
        let success = Self.clean(successCriterion)
        let obstacles = Self.clean(barriers)
        let format = Self.clean(solutionFormat)
        var result = "Помочь \(audience.isEmpty ? "читателю" : audience) \(goal.isEmpty ? "решить практическую задачу" : goal)"
        if !success.isEmpty { result += ", чтобы \(success)" }
        if !obstacles.isEmpty { result += ", учитывая \(obstacles)" }
        if !format.isEmpty { result += ", в формате: \(format)" }
        return result + "."
    }

    func isStale(for topic: Topic) -> Bool {
        Self.normalize(semanticSnapshot) != Self.acceptedSemanticSnapshot(for: topic)
    }

    static func acceptedSemanticSnapshot(for topic: Topic) -> [String] {
        Array(Set(topic.semanticKeywords.compactMap { keyword in
            guard keyword.userDecision == .accepted || keyword.userDecision == .required else { return nil }
            let normalized = clean(keyword.text).lowercased()
            return normalized.isEmpty ? nil : normalized
        })).sorted()
    }

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalize(_ values: [String]) -> [String] {
        Array(Set(values.map { clean($0).lowercased() }.filter { !$0.isEmpty })).sorted()
    }
}
```

Normalization must trim, collapse whitespace, lowercase, deduplicate, and sort accepted/required queries. `taskFormula` is derived, never persisted.

Add to `Topic` and initialize to `nil`:

```swift
@Relationship(deleteRule: .cascade, inverse: \ReaderIntent.topic)
var readerIntent: ReaderIntent?
```

Register `ReaderIntent.self` in `SEOContentCreatorApp`.

- [ ] **Step 4: Register `ReaderIntent.self` in every test container using `Topic.self`**

Insert it immediately after `Topic.self` in:

```text
ArticlePublisherTests.swift
ExternalDocumentTests.swift
FragmentEditTests.swift
GeneratedImageTests.swift
ImageDriveUploaderTests.swift
ImageGeneratorTests.swift
ImagePersistenceModelsTests.swift
ImageSaverTests.swift
ImageSeedingTests.swift
QuickCheckTests.swift
RemarkPersistenceTests.swift
StageExecutorTests.swift
StageTemplateSeederTests.swift
TechInfoSectionBuilderTests.swift
TopicKnowledgeNodeDeletionTests.swift
TopicVersionsTests.swift
VersionActionsTests.swift
```

In each existing `ModelContainer` model list, insert `ReaderIntent.self` immediately after the exact `Topic.self` entry and leave every other registered model in its current order.

- [ ] **Step 5: Run model and schema-heavy suites**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' \
  -only-testing:SEOContentCreatorTests/ReaderIntentTests \
  -only-testing:SEOContentCreatorTests/StageExecutorTests \
  -only-testing:SEOContentCreatorTests/StageTemplateSeederTests \
  -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/ReaderIntent.swift SEOContentCreator/SEOContentCreator/Models/Topic.swift SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift SEOContentCreator/SEOContentCreatorTests
git commit -m "feat: persist reader intent per topic"
```

---

### Task 2: Add reader-intent draft, rendering, parsing, and AI analysis

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentDraft.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentPromptBuilder.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentPromptRenderer.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentResponseParser.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/ReaderIntentAnalyzer.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/ReaderIntentAnalysisTests.swift`

**Interfaces:**
- Consumes: Task 1 types and `StageExecutor.StreamProvider`.
- Produces: `ReaderIntentDraft`, `ReaderIntentPromptBuilder.systemPrompt`, `ReaderIntentPromptBuilder.userPrompt(topic:)`, `ReaderIntentResponseParser.parse(_:)`, `ReaderIntentPromptRenderer.render(topic:)`, `ReaderIntentAnalyzer.analyze(topic:)`.

- [ ] **Step 1: Write failing parser, renderer, and analyzer tests**

```swift
import SwiftData
import Testing
@testable import SEOContentCreator

@MainActor
struct ReaderIntentAnalysisTests {
    @Test func parsesStrictJSONIntoDraft() throws {
        let json = #"{"query":"рак простаты","audienceContext":"пациент","hiddenGoal":"выбрать тактику","successCriterion":"понимает варианты","barriers":"тревога","solutionType":"mixed","solutionFormat":"сравнение","coverage":["definition","risksLimitations"]}"#
        let draft = try ReaderIntentResponseParser.parse(json)
        #expect(draft.solutionType == .mixed)
        #expect(draft.coverage == [.definition, .risksLimitations])
    }

    @Test func rejectsUnknownCoverage() {
        let json = #"{"query":"q","audienceContext":"","hiddenGoal":"g","successCriterion":"","barriers":"","solutionType":"explanation","solutionFormat":"","coverage":["unknown"]}"#
        #expect(throws: ReaderIntentResponseParser.ParserError.badResponse) {
            try ReaderIntentResponseParser.parse(json)
        }
    }

    @Test func rendererOmitsEmptyLinesAndHasEmptyFallback() {
        let topic = Topic(title: "Тема", articleType: .info)
        #expect(ReaderIntentPromptRenderer.render(topic: topic) == "Карта задачи читателя не заполнена.")
        let intent = ReaderIntent(query: "запрос", hiddenGoal: "получить решение")
        intent.coverage = [.practicalSolution]
        topic.readerIntent = intent
        let rendered = ReaderIntentPromptRenderer.render(topic: topic)
        #expect(rendered.contains("- Запрос: запрос"))
        #expect(rendered.contains("- Практическая задача: получить решение"))
        #expect(!rendered.contains("Барьеры и сомнения:"))
    }

    @Test func analyzerSendsOnlyAcceptedAndRequiredSemantics() async throws {
        var capturedUser = ""
        let analyzer = ReaderIntentAnalyzer(
            streamProvider: { _, _, user, _, _, _, _ in
                capturedUser = user
                return AsyncThrowingStream { continuation in
                    continuation.yield(.token(#"{"query":"q","audienceContext":"","hiddenGoal":"g","successCriterion":"","barriers":"","solutionType":"explanation","solutionFormat":"","coverage":[]}"#))
                    continuation.finish()
                }
            },
            keyProvider: { "sk-test" },
            model: "gpt-4.1"
        )
        let topic = Topic(title: "Тема", articleType: .info)
        topic.direction = KnowledgeNode(title: "Онкология", type: .direction, content: "Профиль направления", sources: ["https://example.test/source"])
        topic.doctor = KnowledgeNode(title: "Доктор", type: .doctor, content: "Опыт врача")
        topic.attachedNodes = [KnowledgeNode(title: "Преимущество", type: .advantage, content: "Консилиум")]
        topic.semanticKeywords = [
            SemanticKeyword(text: "принятый", userDecision: .accepted),
            SemanticKeyword(text: "обязательный", userDecision: .required),
            SemanticKeyword(text: "отклонённый", userDecision: .rejected)
        ]
        _ = try await analyzer.analyze(topic: topic)
        #expect(capturedUser.contains("принятый"))
        #expect(capturedUser.contains("обязательный"))
        #expect(!capturedUser.contains("отклонённый"))
        #expect(capturedUser.contains("Профиль направления"))
        #expect(capturedUser.contains("Опыт врача"))
        #expect(capturedUser.contains("Консилиум"))
        #expect(capturedUser.contains("https://example.test/source"))
    }

    @Test func analyzerRejectsEmptyResponse() async {
        let analyzer = ReaderIntentAnalyzer(
            streamProvider: { _, _, _, _, _, _, _ in
                AsyncThrowingStream { $0.finish() }
            },
            keyProvider: { "sk-test" },
            model: "gpt-4.1"
        )
        await #expect(throws: ReaderIntentAnalyzer.AnalyzerError.emptyResponse) {
            try await analyzer.analyze(topic: Topic(title: "Тема", articleType: .info))
        }
    }

    @Test func applyingDraftCapturesCurrentSemanticSnapshot() throws {
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, KnowledgeNode.self, SemanticKeyword.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        topic.semanticKeywords = [SemanticKeyword(text: "  Принятый запрос ", userDecision: .accepted)]
        context.insert(topic)
        var draft = ReaderIntentDraft()
        draft.query = " запрос "
        draft.hiddenGoal = " получить ответ "
        draft.apply(to: topic, source: .manual, in: context)
        #expect(topic.readerIntent?.query == "запрос")
        #expect(topic.readerIntent?.semanticSnapshot == ["принятый запрос"])
        #expect(topic.readerIntent?.source == .manual)
    }
}
```

- [ ] **Step 2: Run and verify compile failure**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ReaderIntentAnalysisTests -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: reader-intent logic types are missing.

- [ ] **Step 3: Implement the draft and explicit apply operation**

```swift
struct ReaderIntentDraft: Equatable {
    var query = ""
    var audienceContext = ""
    var hiddenGoal = ""
    var successCriterion = ""
    var barriers = ""
    var solutionType: ReaderIntentSolutionType = .explanation
    var solutionFormat = ""
    var coverage: Set<ReaderIntentCoverage> = []

    var canSave: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !hiddenGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var taskFormula: String {
        let audience = clean(audienceContext)
        let goal = clean(hiddenGoal)
        let success = clean(successCriterion)
        let obstacles = clean(barriers)
        let format = clean(solutionFormat)
        var result = "Помочь \(audience.isEmpty ? "читателю" : audience) \(goal.isEmpty ? "решить практическую задачу" : goal)"
        if !success.isEmpty { result += ", чтобы \(success)" }
        if !obstacles.isEmpty { result += ", учитывая \(obstacles)" }
        if !format.isEmpty { result += ", в формате: \(format)" }
        return result + "."
    }

    init(intent: ReaderIntent? = nil) {
        guard let intent else { return }
        query = intent.query
        audienceContext = intent.audienceContext
        hiddenGoal = intent.hiddenGoal
        successCriterion = intent.successCriterion
        barriers = intent.barriers
        solutionType = intent.solutionType
        solutionFormat = intent.solutionFormat
        coverage = intent.coverage
    }

    @MainActor
    func apply(to topic: Topic, source: ReaderIntentSource, in context: ModelContext) {
        guard canSave else { return }
        let intent: ReaderIntent
        if let saved = topic.readerIntent {
            intent = saved
        } else {
            intent = ReaderIntent(query: clean(query), hiddenGoal: clean(hiddenGoal))
            intent.topic = topic
            topic.readerIntent = intent
            context.insert(intent)
        }
        intent.query = clean(query)
        intent.audienceContext = clean(audienceContext)
        intent.hiddenGoal = clean(hiddenGoal)
        intent.successCriterion = clean(successCriterion)
        intent.barriers = clean(barriers)
        intent.solutionType = solutionType
        intent.solutionFormat = clean(solutionFormat)
        intent.coverage = coverage
        intent.source = source
        intent.semanticSnapshot = ReaderIntent.acceptedSemanticSnapshot(for: topic)
        intent.updatedAt = .now
        topic.updatedAt = .now
    }

    private func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
```

- [ ] **Step 4: Implement strict parsing, compact rendering, prompt building, and analyzer flow**

Create `ReaderIntentResponseParser.swift`:

```swift
import Foundation

enum ReaderIntentResponseParser {
    enum ParserError: Error, Equatable, LocalizedError {
        case badResponse

        var errorDescription: String? {
            "ИИ вернул ответ в неверном формате. Попробуйте сформировать карту ещё раз."
        }
    }

    private struct Envelope: Decodable {
        var query: String
        var audienceContext: String
        var hiddenGoal: String
        var successCriterion: String
        var barriers: String
        var solutionType: String
        var solutionFormat: String
        var coverage: [String]
    }

    static func parse(_ text: String) throws -> ReaderIntentDraft {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let solutionType = ReaderIntentSolutionType(rawValue: envelope.solutionType)
        else { throw ParserError.badResponse }

        let coverage = envelope.coverage.compactMap(ReaderIntentCoverage.init(rawValue:))
        guard coverage.count == envelope.coverage.count else { throw ParserError.badResponse }

        var draft = ReaderIntentDraft()
        draft.query = clean(envelope.query)
        draft.audienceContext = clean(envelope.audienceContext)
        draft.hiddenGoal = clean(envelope.hiddenGoal)
        draft.successCriterion = clean(envelope.successCriterion)
        draft.barriers = clean(envelope.barriers)
        draft.solutionType = solutionType
        draft.solutionFormat = clean(envelope.solutionFormat)
        draft.coverage = Set(coverage)
        guard draft.canSave else { throw ParserError.badResponse }
        return draft
    }

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
```

Create `ReaderIntentPromptRenderer.swift`:

```swift
enum ReaderIntentPromptRenderer {
    static func render(topic: Topic) -> String {
        guard let intent = topic.readerIntent else {
            return "Карта задачи читателя не заполнена."
        }
        var lines = ["Задача читателя:", "- Запрос: \(intent.query)"]
        append("Кто и в какой ситуации", value: intent.audienceContext, to: &lines)
        append("Практическая задача", value: intent.hiddenGoal, to: &lines)
        append("Ответ полезен, если", value: intent.successCriterion, to: &lines)
        append("Барьеры и сомнения", value: intent.barriers, to: &lines)

        let typeAndFormat = [solutionTitle(intent.solutionType), clean(intent.solutionFormat)]
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
        append("Тип и формат решения", value: typeAndFormat, to: &lines)

        let coverage = ReaderIntentCoverage.allCases
            .filter(intent.coverage.contains)
            .map { coverageTitle($0) }
            .joined(separator: ", ")
        append("Необходимое покрытие", value: coverage, to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func append(_ title: String, value: String, to lines: inout [String]) {
        let value = clean(value)
        if !value.isEmpty { lines.append("- \(title): \(value)") }
    }

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func solutionTitle(_ value: ReaderIntentSolutionType) -> String {
        switch value {
        case .explanation: return "объяснение"
        case .algorithm: return "алгоритм"
        case .comparison: return "сравнение"
        case .directOffer: return "прямое предложение"
        case .mixed: return "смешанный"
        }
    }

    private static func coverageTitle(_ value: ReaderIntentCoverage) -> String {
        switch value {
        case .definition: return "определение"
        case .currentRelevance: return "актуальность сейчас"
        case .choiceComparison: return "выбор и сравнение"
        case .evidence: return "доказательства"
        case .socialProof: return "социальное подтверждение"
        case .applicationContext: return "контекст применения"
        case .risksLimitations: return "риски и ограничения"
        case .practicalSolution: return "практическое решение"
        }
    }
}
```

Create `ReaderIntentPromptBuilder.swift` so stable instructions stay outside dynamic topic data:

```swift
enum ReaderIntentPromptBuilder {
    static let systemPrompt = """
    Ты анализируешь поисковый интент читателя медицинской страницы. Верни только JSON без Markdown.
    Не выдумывай медицинские факты. Неподтверждённые предположения об аудитории, страхах и мотивах формулируй как гипотезы. Не используй запугивание. Выбирай только действительно нужные категории покрытия, а не все восемь по умолчанию.
    Формат ответа:
    Обязательные ключи объекта: query, audienceContext, hiddenGoal, successCriterion, barriers, solutionType, solutionFormat, coverage. Первые семь значений — строки. solutionType — одно из explanation, algorithm, comparison, directOffer, mixed. coverage — массив только из definition, currentRelevance, choiceComparison, evidence, socialProof, applicationContext, risksLimitations, practicalSolution.
    """

    static func userPrompt(topic: Topic) -> String {
        let semantics = ReaderIntent.acceptedSemanticSnapshot(for: topic)
        let semanticText = semantics.isEmpty
            ? "Принятых или обязательных запросов нет; вывод будет менее уверенным."
            : semantics.map { "- \($0)" }.joined(separator: "\n")

        var seen = Set<String>()
        let nodes = ([topic.direction, topic.doctor] + topic.attachedNodes.map(Optional.some))
            .compactMap { $0 }
            .filter { node in
                let key = "\(node.title)\u{0}\(node.content)"
                return seen.insert(key).inserted
            }
        let knowledge = nodes.isEmpty
            ? "(нет прикреплённых данных)"
            : nodes.map { node in
                let body = node.content.isEmpty ? node.title : "\(node.title): \(node.content)"
                let sources = node.sources.isEmpty ? "" : "\nИсточники: \(node.sources.joined(separator: ", "))"
                return "[\(node.nodeType.title)] \(body)\(sources)"
            }.joined(separator: "\n\n")

        return """
        Проанализируй данные темы и заполни одну карту задачи читателя в указанном JSON-формате.

        Тема: \(topic.title)
        Тип статьи: \(topic.articleType.title)

        Принятые и обязательные поисковые запросы:
        \(semanticText)

        Данные этой темы из базы знаний:
        \(knowledge)
        """
    }
}
```

Create `ReaderIntentAnalyzer.swift`:

```swift
import Foundation

@MainActor
struct ReaderIntentAnalyzer {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = StageExecutor.KeyProvider

    enum AnalyzerError: Error, LocalizedError, Equatable {
        case emptyResponse

        var errorDescription: String? {
            "ИИ не вернул карту задачи читателя. Попробуйте ещё раз."
        }
    }

    let streamProvider: StreamProvider
    let keyProvider: KeyProvider
    let model: String

    static func live(model: String) -> ReaderIntentAnalyzer {
        ReaderIntentAnalyzer(
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

    func analyze(topic: Topic) async throws -> ReaderIntentDraft {
        let key = try keyProvider()
        var collected = ""
        for try await event in streamProvider(
            key,
            ReaderIntentPromptBuilder.systemPrompt,
            ReaderIntentPromptBuilder.userPrompt(topic: topic),
            model,
            0.2,
            2500,
            nil
        ) {
            if case .token(let token) = event { collected += token }
        }
        guard !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyzerError.emptyResponse
        }
        return try ReaderIntentResponseParser.parse(collected)
    }
}
```

- [ ] **Step 5: Run reader-intent suites**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' \
  -only-testing:SEOContentCreatorTests/ReaderIntentTests \
  -only-testing:SEOContentCreatorTests/ReaderIntentAnalysisTests \
  -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/ReaderIntent*.swift SEOContentCreator/SEOContentCreatorTests/ReaderIntentAnalysisTests.swift
git commit -m "feat: analyze and render reader intent"
```

---

### Task 3: Integrate reader intent into the current modified prompts

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/TemplateVariables.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/StageTemplateDefaultsTests.swift`

**Interfaces:**
- Consumes: `ReaderIntentPromptRenderer.render(topic:)` from Task 2.
- Produces: `{{задача_читателя}}` substitution and updated factory text for four stages.

- [ ] **Step 1: Add failing prompt-builder tests**

```swift
@Test func substitutesReaderIntentVariable() {
    let template = StageTemplate(stage: .draft, userPromptTemplate: "{{задача_читателя}}")
    let topic = Topic(title: "Тема", articleType: .info)
    topic.readerIntent = ReaderIntent(query: "запрос", hiddenGoal: "решить задачу")
    let result = PromptBuilder().build(template: template, topic: topic, currentText: nil)
    #expect(result.user.contains("Практическая задача: решить задачу"))
}

@Test func missingReaderIntentUsesExplicitFallback() {
    let template = StageTemplate(stage: .structure, userPromptTemplate: "{{задача_читателя}}")
    let topic = Topic(title: "Тема", articleType: .info)
    let result = PromptBuilder().build(template: template, topic: topic, currentText: nil)
    #expect(result.user == "Карта задачи читателя не заполнена.")
}

@Test func unrelatedStageDoesNotReceiveReaderIntentEvenWithManualToken() {
    let template = StageTemplate(stage: .factCheck, userPromptTemplate: "До {{задача_читателя}} После")
    let topic = Topic(title: "Тема", articleType: .info)
    topic.readerIntent = ReaderIntent(query: "запрос", hiddenGoal: "решить задачу")
    let result = PromptBuilder().build(template: template, topic: topic, currentText: "Текст")
    #expect(result.user == "До  После")
}
```

- [ ] **Step 2: Add failing default-prompt tests**

```swift
@Test func readerIntentAppearsOnlyInRelevantStages() {
    let included: Set<PipelineStage> = [.structure, .draft, .semanticsInText, .seoCheck]
    for stage in PipelineStage.allCases where stage.kind != .action {
        let prompt = StageTemplateDefaults.content(for: stage).userPromptTemplate
        let contains = prompt.contains("{{задача_читателя}}")
        #expect(contains == included.contains(stage))
        if included.contains(stage) {
            #expect(prompt.contains("<!-- reader-intent-v1:\(stage.rawValue) -->"))
        }
    }
}

@Test func structureUsesSemanticsAsOrientationNotMandatoryKeys() {
    let prompt = StageTemplateDefaults.content(for: .structure).userPromptTemplate
    #expect(prompt.contains("{{семантика}}"))
    #expect(prompt.contains("ориентир"))
    #expect(prompt.contains("не список обязательных"))
    #expect(!prompt.contains("блок «Полезное действие»"))
}

@Test func seoCheckAddsIntentAndCompletenessCategories() {
    let prompt = StageTemplateDefaults.content(for: .seoCheck).userPromptTemplate
    #expect(prompt.contains("«Интент»"))
    #expect(prompt.contains("«Полнота»"))
}
```

- [ ] **Step 3: Run both suites and verify failures**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' \
  -only-testing:SEOContentCreatorTests/PromptBuilderTests \
  -only-testing:SEOContentCreatorTests/StageTemplateDefaultsTests \
  -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: missing substitution and outdated prompt assertions fail.

- [ ] **Step 4: Register and substitute the variable**

Add to `TemplateVariables.all`:

```swift
TemplateVariable(
    token: "{{задача_читателя}}",
    description: "Сохранённая карта задачи читателя",
    source: "Подготовка статьи → Задача читателя"
)
```

Immediately before the existing `substitutions` dictionary in `PromptBuilder.build`, add:

```swift
let readerIntentStages: Set<PipelineStage> = [.structure, .draft, .semanticsInText, .seoCheck]
let readerIntent = template.stage.map { readerIntentStages.contains($0) } == true
    ? ReaderIntentPromptRenderer.render(topic: topic)
    : ""
```

Then add this entry to the existing dictionary without changing its other entries:

```swift
"{{задача_читателя}}": readerIntent,
```

- [ ] **Step 5: Modify the four current default prompts in place**

Retain every unrelated current line. In Structure, replace the current `Полезное действие` block and final `Не добавляй ключевые запросы` line with these exact inputs and output rule:

```text
<!-- reader-intent-v1:structure -->
{{задача_читателя}}

Поисковые запросы — ориентир для понимания вопросов и контекста читателя, а не список обязательных заголовков или точных фраз:
{{семантика}}

Используй выбранное семантическое покрытие как проверку полноты, но не превращай названия категорий в обязательные разделы. Верни только структуру H1/H2/H3 с пометками; карту задачи в результат не включай.
```

In Draft, replace the current conditional paragraph about a `Полезное действие` block with:

```text
<!-- reader-intent-v1:draft -->
{{задача_читателя}}

Используй карту как рамку текста: каждый раздел помогает достичь критерия полезного ответа или снять значимый барьер. Саму карту в статью не включай.
```

In Semantics-in-text, insert this immediately before `Текущий текст:`:

```text
<!-- reader-intent-v1:semanticsInText -->
{{задача_читателя}}
```

Replace the existing `Требования к H1, Title и Description` paragraph with this merged wording, avoiding a duplicate benefit rule:

```text
Требования к H1, Title и Description: кроме ключей они должны отражать практическую задачу читателя и обещать конкретную пользу — что он узнает, сэкономит или решит, — без неподтверждённых обещаний. Description отвечает на вопрос «почему стоит открыть именно эту страницу» — без рекламных преувеличений и кликбейта.
```

In SEO-check, insert this immediately before `Текст:`:

```text
<!-- reader-intent-v1:seoCheck -->
{{задача_читателя}}

Проверь, отвечает ли страница практическому интенту и покрывает ли выбранные в карте типы информации. Не требуй категории, которые в карте не выбраны.
```

Extend the existing SEO category line with `«Интент», «Полнота»`, and replace the old test that asserted semantics were absent.

- [ ] **Step 6: Run prompt suites**

Run the Step 3 command again.

Expected: all selected tests pass and current unrelated prompt requirements remain green.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/TemplateVariables.swift SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift SEOContentCreator/SEOContentCreatorTests/StageTemplateDefaultsTests.swift
git commit -m "feat: guide article stages with reader intent"
```

---

### Task 4: Add full personal-default snapshots and a testable service

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Models/StageTemplate.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/AIRole.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/ContextBlock.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/PromptPersonalDefaultsService.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/PromptPersonalDefaultsTests.swift`

**Interfaces:**
- Produces: `PromptEditorState` full value snapshot.
- Produces: `PromptPersonalDefaultsService.liveState`, `.saveAsPersonalDefault`, `.personalDefaultState`, `.factoryState`, `.captureIfMissing`.
- Consumes: existing `SharedFieldUpdate` for shared-version increments.

- [ ] **Step 1: Write failing full-snapshot tests**

```swift
import Testing
@testable import SEOContentCreator

struct PromptPersonalDefaultsTests {
    @Test func saveUpdatesLiveStateAndFullPersonalDefault() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "old")
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "old role", blockKeys: [])
        let block = ContextBlock(key: "sources", title: "Источники", text: "old block")
        let state = PromptEditorState(
            userPromptTemplate: "new", modelName: "gpt-5.5", temperature: 0.3,
            maxTokens: 12000, reasoningEffort: "high", mandate: "new role",
            enabledBlockKeys: ["sources"], blockTexts: ["sources": "new block"]
        )
        PromptPersonalDefaultsService.saveAsPersonalDefault(
            state, template: template, role: role, blocks: [block]
        )
        #expect(template.userPromptTemplate == "new")
        #expect(template.personalDefaultUserPromptTemplate == "new")
        #expect(template.personalDefaultReasoningEffort == "high")
        #expect(role.personalDefaultMandate == "new role")
        #expect(role.personalDefaultBlockKeys == ["sources"])
        #expect(block.personalDefaultText == "new block")
        #expect(template.hasPersonalDefault && role.hasPersonalDefault && block.hasPersonalDefault)
    }

    @Test func personalRestoreReturnsValueWithoutMutatingLiveObjects() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "live")
        template.hasPersonalDefault = true
        template.personalDefaultUserPromptTemplate = "personal"
        template.personalDefaultModelName = "gpt-4.1"
        template.personalDefaultTemperature = 0.6
        template.personalDefaultMaxTokens = 8000
        let state = PromptPersonalDefaultsService.personalDefaultState(
            template: template, role: nil, blocks: []
        )
        #expect(state?.userPromptTemplate == "personal")
        #expect(template.userPromptTemplate == "live")
    }

    @Test func factoryRestoreReturnsCurrentCodeDefaultsWithoutMutation() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "live")
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "live role", blockKeys: [])
        let block = ContextBlock(key: "sources", title: "Источники", text: "live block")
        let state = PromptPersonalDefaultsService.factoryState(stage: .draft, role: role, blocks: [block])
        #expect(state.userPromptTemplate == StageTemplateDefaults.content(for: .draft).userPromptTemplate)
        #expect(state.mandate == RoleDefaults.defaultForKey("author")?.mandate)
        #expect(state.blockTexts["sources"] == ContextBlockDefaults.defaultForKey("sources")?.text)
        #expect(template.userPromptTemplate == "live")
    }

    @Test func savingOnlyStageFieldsDoesNotBumpUnchangedSharedVersions() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "old")
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "same", blockKeys: ["sources"], version: 4)
        let block = ContextBlock(key: "sources", title: "Источники", text: "same block", version: 7)
        let state = PromptEditorState(
            userPromptTemplate: "new", modelName: "gpt-4.1", temperature: 0.6,
            maxTokens: 8000, reasoningEffort: nil, mandate: "same",
            enabledBlockKeys: ["sources"], blockTexts: ["sources": "same block"]
        )
        PromptPersonalDefaultsService.saveAsPersonalDefault(
            state, template: template, role: role, blocks: [block]
        )
        #expect(role.version == 4)
        #expect(block.version == 7)
    }

    @Test func captureIfMissingNeverOverwritesExistingPersonalDefault() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "live v1")
        PromptPersonalDefaultsService.captureIfMissing(template: template, role: nil, blocks: [])
        template.userPromptTemplate = "live v2"
        PromptPersonalDefaultsService.captureIfMissing(template: template, role: nil, blocks: [])
        #expect(template.personalDefaultUserPromptTemplate == "live v1")
    }
}
```

- [ ] **Step 2: Run and verify compile failures**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptPersonalDefaultsTests -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: snapshot fields and service are undefined.

- [ ] **Step 3: Add lightweight snapshot fields**

Add to `StageTemplate`:

```swift
var hasPersonalDefault: Bool = false
var personalDefaultUserPromptTemplate: String?
var personalDefaultModelName: String?
var personalDefaultTemperature: Double?
var personalDefaultMaxTokens: Int?
var personalDefaultReasoningEffort: String?
var personalDefaultUpdatedAt: Date?
```

Add to `AIRole`:

```swift
var hasPersonalDefault: Bool = false
var personalDefaultMandate: String?
var personalDefaultBlockKeys: [String] = []
var personalDefaultUpdatedAt: Date?
```

Add to `ContextBlock`:

```swift
var hasPersonalDefault: Bool = false
var personalDefaultText: String?
var personalDefaultUpdatedAt: Date?
```

- [ ] **Step 4: Implement immutable editor state and service**

```swift
struct PromptEditorState: Equatable {
    var userPromptTemplate: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var reasoningEffort: String?
    var mandate: String
    var enabledBlockKeys: [String]
    var blockTexts: [String: String]
}

enum PromptPersonalDefaultsService {
    static func liveState(
        template: StageTemplate,
        role: AIRole?,
        blocks: [ContextBlock]
    ) -> PromptEditorState {
        PromptEditorState(
            userPromptTemplate: template.userPromptTemplate,
            modelName: template.modelName,
            temperature: template.temperature,
            maxTokens: template.maxTokens,
            reasoningEffort: template.reasoningEffort,
            mandate: role?.mandate ?? "",
            enabledBlockKeys: role?.blockKeys ?? [],
            blockTexts: Dictionary(uniqueKeysWithValues: blocks.map { ($0.key, $0.text) })
        )
    }

    static func saveAsPersonalDefault(
        _ state: PromptEditorState,
        template: StageTemplate,
        role: AIRole?,
        blocks: [ContextBlock]
    ) {
        let now = Date.now
        template.userPromptTemplate = state.userPromptTemplate
        template.modelName = state.modelName
        template.temperature = state.temperature
        template.maxTokens = state.maxTokens
        template.reasoningEffort = state.reasoningEffort
        template.templateVersion += 1
        template.updatedAt = now
        template.hasPersonalDefault = true
        template.personalDefaultUserPromptTemplate = state.userPromptTemplate
        template.personalDefaultModelName = state.modelName
        template.personalDefaultTemperature = state.temperature
        template.personalDefaultMaxTokens = state.maxTokens
        template.personalDefaultReasoningEffort = state.reasoningEffort
        template.personalDefaultUpdatedAt = now

        if let role {
            if let change = SharedFieldUpdate.roleUpdate(
                current: role,
                mandate: state.mandate,
                blockKeys: state.enabledBlockKeys
            ) {
                role.mandate = change.mandate
                role.blockKeys = change.blockKeys
                role.version = change.version
                role.updatedAt = now
            }
            role.hasPersonalDefault = true
            role.personalDefaultMandate = state.mandate
            role.personalDefaultBlockKeys = state.enabledBlockKeys
            role.personalDefaultUpdatedAt = now
        }

        for block in blocks {
            let text = state.blockTexts[block.key] ?? block.text
            if let change = SharedFieldUpdate.blockUpdate(current: block, text: text) {
                block.text = change.text
                block.version = change.version
                block.updatedAt = now
            }
            block.hasPersonalDefault = true
            block.personalDefaultText = text
            block.personalDefaultUpdatedAt = now
        }
    }

    static func personalDefaultState(
        template: StageTemplate,
        role: AIRole?,
        blocks: [ContextBlock]
    ) -> PromptEditorState? {
        guard template.hasPersonalDefault,
              let user = template.personalDefaultUserPromptTemplate,
              let model = template.personalDefaultModelName,
              let temperature = template.personalDefaultTemperature,
              let maxTokens = template.personalDefaultMaxTokens,
              let blockTexts = personalBlockTexts(blocks)
        else { return nil }
        if let role {
            guard role.hasPersonalDefault, let mandate = role.personalDefaultMandate else { return nil }
            return PromptEditorState(
                userPromptTemplate: user,
                modelName: model,
                temperature: temperature,
                maxTokens: maxTokens,
                reasoningEffort: template.personalDefaultReasoningEffort,
                mandate: mandate,
                enabledBlockKeys: role.personalDefaultBlockKeys,
                blockTexts: blockTexts
            )
        }
        return PromptEditorState(
            userPromptTemplate: user,
            modelName: model,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoningEffort: template.personalDefaultReasoningEffort,
            mandate: "",
            enabledBlockKeys: [],
            blockTexts: blockTexts
        )
    }

    static func factoryState(
        stage: PipelineStage,
        role: AIRole?,
        blocks: [ContextBlock]
    ) -> PromptEditorState {
        let template = StageTemplateDefaults.content(for: stage)
        let roleDefault = role.flatMap { RoleDefaults.defaultForKey($0.key) }
        return PromptEditorState(
            userPromptTemplate: template.userPromptTemplate,
            modelName: template.modelName,
            temperature: template.temperature,
            maxTokens: template.maxTokens,
            reasoningEffort: template.reasoningEffort,
            mandate: roleDefault?.mandate ?? role?.mandate ?? "",
            enabledBlockKeys: roleDefault?.blockKeys ?? role?.blockKeys ?? [],
            blockTexts: Dictionary(uniqueKeysWithValues: blocks.map { block in
                (block.key, ContextBlockDefaults.defaultForKey(block.key)?.text ?? block.text)
            })
        )
    }

    static func captureIfMissing(
        template: StageTemplate,
        role: AIRole?,
        blocks: [ContextBlock]
    ) {
        let now = Date.now
        if !template.hasPersonalDefault {
            template.hasPersonalDefault = true
            template.personalDefaultUserPromptTemplate = template.userPromptTemplate
            template.personalDefaultModelName = template.modelName
            template.personalDefaultTemperature = template.temperature
            template.personalDefaultMaxTokens = template.maxTokens
            template.personalDefaultReasoningEffort = template.reasoningEffort
            template.personalDefaultUpdatedAt = now
        }
        if let role, !role.hasPersonalDefault {
            role.hasPersonalDefault = true
            role.personalDefaultMandate = role.mandate
            role.personalDefaultBlockKeys = role.blockKeys
            role.personalDefaultUpdatedAt = now
        }
        for block in blocks where !block.hasPersonalDefault {
            block.hasPersonalDefault = true
            block.personalDefaultText = block.text
            block.personalDefaultUpdatedAt = now
        }
    }

    private static func personalBlockTexts(_ blocks: [ContextBlock]) -> [String: String]? {
        var result: [String: String] = [:]
        for block in blocks {
            guard block.hasPersonalDefault, let text = block.personalDefaultText else { return nil }
            result[block.key] = text
        }
        return result
    }
}
```

`saveAsPersonalDefault` increments the stage version on each explicit save, uses `SharedFieldUpdate` to increment role/block versions only for live changes, and always refreshes all snapshot fields. `personalDefaultState` returns `nil` unless the template and every supplied shared object have complete snapshots; this prevents a mixed state.

- [ ] **Step 5: Run personal-default and shared-update suites**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' \
  -only-testing:SEOContentCreatorTests/PromptPersonalDefaultsTests \
  -only-testing:SEOContentCreatorTests/SharedFieldUpdateTests \
  -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/StageTemplate.swift SEOContentCreator/SEOContentCreator/Models/AIRole.swift SEOContentCreator/SEOContentCreator/Models/ContextBlock.swift SEOContentCreator/SEOContentCreator/Logic/PromptPersonalDefaultsService.swift SEOContentCreator/SEOContentCreatorTests/PromptPersonalDefaultsTests.swift
git commit -m "feat: store full personal prompt defaults"
```

---

### Task 5: Replace cascade overwrite with an idempotent v9 upgrade

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/StagePromptIntentMigration.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/StagePromptIntentMigrationTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/StageTemplateSeederTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/TemplatesMigrationV3Tests.swift`

**Interfaces:**
- Consumes: Task 3 factory prompts and Task 4 snapshot service.
- Produces: `StagePromptIntentMigration.upgrade(_:for:)` and template-defaults version 9.

- [ ] **Step 1: Write failing additive/idempotent migration tests**

```swift
import Testing
@testable import SEOContentCreator

struct StagePromptIntentMigrationTests {
    @Test func upgradesCustomizedStructureWithoutReplacingExistingText() {
        let original = "Мой изменённый промт структуры. Верни Markdown."
        let upgraded = StagePromptIntentMigration.upgrade(original, for: .structure)
        #expect(upgraded.contains(original))
        #expect(upgraded.contains("{{задача_читателя}}"))
        #expect(upgraded.contains("{{семантика}}"))
    }

    @Test func upgradeIsIdempotent() {
        let first = StagePromptIntentMigration.upgrade("Мой промт", for: .seoCheck)
        let second = StagePromptIntentMigration.upgrade(first, for: .seoCheck)
        #expect(second == first)
        #expect(second.components(separatedBy: "{{задача_читателя}}").count == 2)
    }

    @Test func unrelatedStageIsUnchanged() {
        #expect(StagePromptIntentMigration.upgrade("Фактчек", for: .factCheck) == "Фактчек")
    }
}
```

- [ ] **Step 2: Replace old overwrite expectations**

In `StageTemplateSeederTests`, create a stored-version-8 draft containing `Пользовательский {{тема}}`, run the seeder, and assert:

```swift
#expect(old.userPromptTemplate.contains("Пользовательский {{тема}}"))
#expect(old.userPromptTemplate.contains("{{задача_читателя}}"))
#expect(old.hasPersonalDefault)
#expect(old.personalDefaultUserPromptTemplate == old.userPromptTemplate)
#expect(defaults.integer(forKey: StageTemplateSeeder.templatesDefaultsVersionKey) == 9)
```

Update hard-coded expected versions from `8` to `9`. Replace `TemplatesMigrationV3Tests.overwritesCascadeTemplatesAndBlocks` with preservation assertions for modified prompt, role, and block text plus first-snapshot equality.

- [ ] **Step 3: Run migration suites and verify failure**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' \
  -only-testing:SEOContentCreatorTests/StagePromptIntentMigrationTests \
  -only-testing:SEOContentCreatorTests/StageTemplateSeederTests \
  -only-testing:SEOContentCreatorTests/TemplatesMigrationV3Tests \
  -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: old overwrite behavior and version-8 assertions fail.

- [ ] **Step 4: Implement stage-specific marked additions**

```swift
enum StagePromptIntentMigration {
    static func upgrade(_ text: String, for stage: PipelineStage) -> String {
        guard let addition = addition(for: stage) else { return text }
        let marker = "<!-- reader-intent-v1:\(stage.rawValue) -->"
        guard !text.contains(marker) else { return text }
        return insertAtKnownAnchor(text, addition: addition, stage: stage)
            ?? text + "\n\n" + addition
    }

    private static func addition(for stage: PipelineStage) -> String? {
        switch stage {
        case .structure:
            return """
            <!-- reader-intent-v1:structure -->
            {{задача_читателя}}

            Поисковые запросы — ориентир для понимания вопросов и контекста читателя, а не список обязательных заголовков или точных фраз:
            {{семантика}}

            Используй выбранное семантическое покрытие как проверку полноты, но не превращай названия категорий в обязательные разделы. Верни только структуру H1/H2/H3 с пометками; карту задачи в результат не включай.
            """
        case .draft:
            return """
            <!-- reader-intent-v1:draft -->
            {{задача_читателя}}

            Используй карту как рамку текста: каждый раздел помогает достичь критерия полезного ответа или снять значимый барьер. Саму карту в статью не включай.
            """
        case .semanticsInText:
            return """
            <!-- reader-intent-v1:semanticsInText -->
            {{задача_читателя}}

            H1, Title и Description должны отражать практическую задачу читателя без неподтверждённых обещаний.
            """
        case .seoCheck:
            return """
            <!-- reader-intent-v1:seoCheck -->
            {{задача_читателя}}

            Проверь, отвечает ли страница практическому интенту и покрывает ли выбранные в карте типы информации. Не требуй категории, которые в карте не выбраны. Для замечаний по этим критериям используй категории «Интент» и «Полнота».
            """
        default:
            return nil
        }
    }

    private static func insertAtKnownAnchor(
        _ text: String,
        addition: String,
        stage: PipelineStage
    ) -> String? {
        let anchor: String
        switch stage {
        case .structure:
            anchor = "Не добавляй ключевые запросы. Формат — Markdown."
        case .draft:
            anchor = "{{структура}}"
        case .semanticsInText:
            anchor = "Текущий текст:"
        case .seoCheck:
            anchor = "Текст:"
        default:
            return nil
        }
        guard let range = text.range(of: anchor) else { return nil }
        return String(text[..<range.upperBound]) + "\n\n" + addition + String(text[range.upperBound...])
    }
}
```

The fallback append preserves the original text byte-for-byte as a prefix. The stage-specific marker makes both anchored and fallback upgrades idempotent.

- [ ] **Step 5: Refactor seeding to version 9 without full replacement**

Change the version constant:

```swift
private static let currentTemplatesDefaultsVersion = 9
```

Replace the old cascade-template, context-block, and role-overwrite section at the start of `migrateTemplatesIfNeeded` with this code:

```swift
let templates = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
for template in templates {
    guard let stage = template.stage else { continue }
    template.userPromptTemplate = StagePromptIntentMigration.upgrade(template.userPromptTemplate, for: stage)
    template.updatedAt = .now
}

let blocks = (try? context.fetch(FetchDescriptor<ContextBlock>())) ?? []
var roles = (try? context.fetch(FetchDescriptor<AIRole>())) ?? []
if !roles.isEmpty,
   !roles.contains(where: { $0.key == "analyst" }),
   let definition = RoleDefaults.defaultForKey("analyst") {
    let analyst = AIRole(
        key: definition.key,
        name: definition.name,
        mandate: definition.mandate,
        blockKeys: definition.blockKeys
    )
    context.insert(analyst)
    roles.append(analyst)
}

for template in templates {
    guard let stage = template.stage else { continue }
    let role = roles.first { $0.key == stage.roleKey }
    PromptPersonalDefaultsService.captureIfMissing(template: template, role: role, blocks: blocks)
}
```

Leave the existing missing skill-preset and style-preset additions below this replacement. Replace the existing unconditional image-prompt loop with the exact guarded block below, so an installation already on version 8 does not have image prompts rewritten again during the v9 migration. Keep the final version write shown after it:

```swift
if storedVersion < 8 {
    let imagePrompts = (try? context.fetch(FetchDescriptor<ImagePromptTemplate>())) ?? []
    for template in imagePrompts {
        guard let kind = template.kind else { continue }
        template.userPromptTemplate = ImagePromptDefaults.content(for: kind)
        template.updatedAt = .now
    }
}

defaults.set(currentTemplatesDefaultsVersion, forKey: templatesDefaultsVersionKey)
```

Delete the old full assignments from `StageTemplateDefaults`, `ContextBlockDefaults`, and `RoleDefaults`. Fresh stage prompts already contain markers; migration leaves their text unchanged and captures their first personal default. Existing modified prompts retain all original text and receive only the marked stage-specific addition.

- [ ] **Step 6: Run migration suites twice**

Run Step 3 twice without code changes.

Expected: all tests pass both times with no duplicates or state drift.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StagePromptIntentMigration.swift SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift SEOContentCreator/SEOContentCreatorTests/StagePromptIntentMigrationTests.swift SEOContentCreator/SEOContentCreatorTests/StageTemplateSeederTests.swift SEOContentCreator/SEOContentCreatorTests/TemplatesMigrationV3Tests.swift
git commit -m "feat: migrate prompts without overwriting edits"
```

---

### Task 6: Build the reader-intent editor and workspace preparation UI

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/ReaderIntentSheet.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/StageRailView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/StructureEditorSheet.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/ReaderIntent.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/ReaderIntentTests.swift`

**Interfaces:**
- Consumes: `ReaderIntentDraft`, `ReaderIntentAnalyzer`, `ReaderIntent.isStale`, and `ReaderIntentDraft.apply`.
- Produces: `ReaderIntentSheet(topic:)`, `ReaderIntentStatus.forTopic(_:)`, and StageRail callbacks `openSemantics`, `openReaderIntent`.

- [ ] **Step 1: Add failing pure status tests**

```swift
@Test func presentationStatusCoversMissingReadyAndStale() {
    let topic = Topic(title: "Тема", articleType: .info)
    #expect(ReaderIntentStatus.forTopic(topic) == .missing)
    let intent = ReaderIntent(query: "q", hiddenGoal: "понять решение")
    intent.semanticSnapshot = []
    topic.readerIntent = intent
    #expect(ReaderIntentStatus.forTopic(topic) == .ready(summary: "понять решение"))
    topic.semanticKeywords = [SemanticKeyword(text: "новый", userDecision: .accepted)]
    #expect(ReaderIntentStatus.forTopic(topic) == .stale(summary: "понять решение"))
}
```

- [ ] **Step 2: Run and verify the status test fails**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ReaderIntentTests -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: `ReaderIntentStatus.forTopic` is missing.

- [ ] **Step 3: Implement the editor sheet with local draft ownership**

Add this pure presentation state next to `ReaderIntent` in `ReaderIntent.swift`:

```swift
enum ReaderIntentStatus: Equatable {
    case missing
    case ready(summary: String)
    case stale(summary: String)

    static func forTopic(_ topic: Topic) -> ReaderIntentStatus {
        guard let intent = topic.readerIntent else { return .missing }
        let summary = intent.hiddenGoal
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return intent.isStale(for: topic) ? .stale(summary: summary) : .ready(summary: summary)
    }
}
```

Create `ReaderIntentSheet.swift`:

```swift
import SwiftData
import SwiftUI

struct ReaderIntentSheet: View {
@Environment(\.dismiss) private var dismiss
@Environment(\.modelContext) private var context
@Bindable var topic: Topic
@AppStorage("openAIModel") private var model = "gpt-4.1"
@State private var draft = ReaderIntentDraft(intent: nil)
@State private var draftSource: ReaderIntentSource = .manual
@State private var isRunning = false
@State private var errorMessage: String?

    private var hasSemanticEvidence: Bool {
        !ReaderIntent.acceptedSemanticSnapshot(for: topic).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Задача читателя").font(.title2.bold())
                        Text("Карта помогает структуре и тексту отвечать на практический поисковый интент.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: generate) {
                        Label(
                            topic.readerIntent == nil ? "Сформировать с ИИ" : "Обновить с ИИ",
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(isRunning)
                }

                if !hasSemanticEvidence {
                    Label(
                        "Принятых или обязательных запросов пока нет. ИИ сможет сделать черновик, но уверенность будет ниже.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }

                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("ИИ формирует черновик. Текущие поля остаются доступными для просмотра.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                        .font(.callout).foregroundStyle(.red)
                }

                GroupBox("Основная задача") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Поисковый запрос", text: $draft.query)
                        field("Кто читатель и в какой ситуации", text: $draft.audienceContext, height: 64)
                        field("Практическая задача", text: $draft.hiddenGoal, height: 72)
                        field("Ответ полезен, если…", text: $draft.successCriterion, height: 64)
                        field("Барьеры и сомнения", text: $draft.barriers, height: 72)
                    }
                    .padding(.top, 6)
                }

                GroupBox("Форма решения") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Тип решения", selection: $draft.solutionType) {
                            ForEach(ReaderIntentSolutionType.allCases) { value in
                                Text(solutionTitle(value)).tag(value)
                            }
                        }
                        TextField("Формат: сравнение, алгоритм, объяснение…", text: $draft.solutionFormat)
                    }
                    .padding(.top, 6)
                }

                GroupBox("Необходимое покрытие") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                        ForEach(ReaderIntentCoverage.allCases) { value in
                            Toggle(coverageTitle(value), isOn: coverageBinding(value))
                                .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("Формула задачи") {
                    Text(draft.taskFormula)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || !draft.canSave)
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .frame(width: 760, height: 720)
        .onAppear(perform: load)
    }

    private func field(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: height)
                .padding(5)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func coverageBinding(_ value: ReaderIntentCoverage) -> Binding<Bool> {
        Binding(
            get: { draft.coverage.contains(value) },
            set: { enabled in
                if enabled { draft.coverage.insert(value) } else { draft.coverage.remove(value) }
            }
        )
    }

    private func load() {
        draft = ReaderIntentDraft(intent: topic.readerIntent)
        draftSource = topic.readerIntent?.source ?? .manual
    }

    private func generate() {
        isRunning = true
        errorMessage = nil
        Task {
            defer { isRunning = false }
            do {
                draft = try await ReaderIntentAnalyzer.live(model: model).analyze(topic: topic)
                draftSource = .ai
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        errorMessage = nil
        do {
            draft.apply(to: topic, source: draftSource, in: context)
            try context.save()
            dismiss()
        } catch {
            errorMessage = "Не удалось сохранить карту: \(error.localizedDescription)"
        }
    }

    private func solutionTitle(_ value: ReaderIntentSolutionType) -> String {
        switch value {
        case .explanation: return "Объяснение"
        case .algorithm: return "Алгоритм"
        case .comparison: return "Сравнение"
        case .directOffer: return "Прямое предложение"
        case .mixed: return "Смешанный"
        }
    }

    private func coverageTitle(_ value: ReaderIntentCoverage) -> String {
        switch value {
        case .definition: return "Определение"
        case .currentRelevance: return "Актуальность сейчас"
        case .choiceComparison: return "Выбор и сравнение"
        case .evidence: return "Доказательства"
        case .socialProof: return "Социальное подтверждение"
        case .applicationContext: return "Контекст применения"
        case .risksLimitations: return "Риски и ограничения"
        case .practicalSolution: return "Практическое решение"
        }
    }
}
```

- [ ] **Step 4: Add preparation rows without changing `PipelineStage`**

Change the StageRail interface exactly to:

```swift
struct StageRailView: View {
    @Binding var selectedStage: PipelineStage
    var topic: Topic
    var openSemantics: () -> Void
    var openReaderIntent: () -> Void
    @Query private var roles: [AIRole]
}
```

Before the existing `Этапы` header, render `Подготовка статьи`, a `Семантика` button, and a `Задача читателя` button. Use status icons and these subtitles: `Не заполнена`, the one-line hidden-goal summary, or `Семантика изменилась`. Do not alter stage completion counts. Insert these two lines as the first children of the rail's outer `VStack`:

```swift
preparationSection
Divider().padding(.vertical, 6)
```

Add these exact helpers:

```swift
private var preparationSection: some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("Подготовка статьи")
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)

        Button(action: openSemantics) {
            preparationRow(
                title: "Семантика",
                subtitle: topic.semanticKeywords.isEmpty ? "Не заполнена" : "Запросов: \(topic.semanticKeywords.count)",
                icon: topic.semanticKeywords.isEmpty ? "circle" : "checkmark.circle.fill",
                color: topic.semanticKeywords.isEmpty ? .secondary : .green
            )
        }
        .buttonStyle(.plain)

        Button(action: openReaderIntent) {
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
        .buttonStyle(.plain)
    }
}

private func preparationRow(
    title: String,
    subtitle: String,
    icon: String,
    color: Color
) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
            .foregroundStyle(color)
            .font(.title3)
            .frame(width: 22, height: 22)
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.body.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 9)
    .contentShape(Rectangle())
}
```

- [ ] **Step 5: Wire the topic workspace**

Add:

```swift
@State private var showReaderIntent = false
```

Replace the StageRail call with:

```swift
StageRailView(
    selectedStage: $selectedStage,
    topic: topic,
    openSemantics: {
        inspectorTab = .semantics
        showInspector = true
    },
    openReaderIntent: { showReaderIntent = true }
)
```

Add:

```swift
.sheet(isPresented: $showReaderIntent) { ReaderIntentSheet(topic: topic) }
```

- [ ] **Step 6: Add the non-blocking structure banner**

In `StructureEditorSheet`, add:

```swift
@State private var showReaderIntent = false
```

Insert `intentBanner` directly below the existing title/generate `HStack`, add the sheet modifier, and add the exact banner implementation:

```swift
.sheet(isPresented: $showReaderIntent) {
    ReaderIntentSheet(topic: topic)
}

@ViewBuilder
private var intentBanner: some View {
    switch ReaderIntentStatus.forTopic(topic) {
    case .missing:
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Задача читателя не заполнена. Структуру можно создать, но рамка интента не попадёт в промт.")
                .font(.callout)
            Spacer()
            Button("Заполнить") { showReaderIntent = true }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    case .ready(let summary):
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(summary).font(.callout).lineLimit(2)
            Spacer()
            Button("Редактировать") { showReaderIntent = true }
        }
        .padding(10)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    case .stale(let summary):
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Семантика изменилась — рекомендуется обновить. \(summary)")
                .font(.callout).lineLimit(2)
            Spacer()
            Button("Редактировать") { showReaderIntent = true }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
```

Do not add a guard to `generate()` and do not disable its button when intent is missing.

- [ ] **Step 7: Run tests and compile the UI**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ReaderIntentTests -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: tests pass and `** TEST BUILD SUCCEEDED **` appears.

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/ReaderIntentSheet.swift SEOContentCreator/SEOContentCreator/Views/StageRailView.swift SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift SEOContentCreator/SEOContentCreator/Views/StructureEditorSheet.swift SEOContentCreator/SEOContentCreator/Models/ReaderIntent.swift SEOContentCreator/SEOContentCreatorTests/ReaderIntentTests.swift
git commit -m "feat: add reader intent preparation workflow"
```

---

### Task 7: Update the prompt editor for personal and factory defaults

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/Templates/StagePromptEditorView.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/PromptPersonalDefaultsTests.swift`

**Interfaces:**
- Consumes: `PromptEditorState` and `PromptPersonalDefaultsService` from Task 4.
- Produces: full Save-as-personal-default UI, non-persisting personal restore, and non-persisting factory restore with a shared-data warning.

- [ ] **Step 1: Add a failing full factory round-trip test**

```swift
@Test func factoryThenSaveBecomesNewPersonalDefault() {
    let template = StageTemplate(stage: .seoCheck, userPromptTemplate: "custom")
    let role = AIRole(key: "seo", name: "ИИ-SEO", mandate: "custom role", blockKeys: [])
    let block = ContextBlock(key: "seoGuidelines", title: "SEO-рекомендации", text: "custom block")
    let factory = PromptPersonalDefaultsService.factoryState(stage: .seoCheck, role: role, blocks: [block])
    #expect(template.userPromptTemplate == "custom")
    PromptPersonalDefaultsService.saveAsPersonalDefault(factory, template: template, role: role, blocks: [block])
    #expect(template.personalDefaultUserPromptTemplate == StageTemplateDefaults.content(for: .seoCheck).userPromptTemplate)
    #expect(role.personalDefaultMandate == RoleDefaults.defaultForKey("seo")?.mandate)
    #expect(block.personalDefaultText == ContextBlockDefaults.defaultForKey("seoGuidelines")?.text)
}
```

- [ ] **Step 2: Run the service test before editing SwiftUI**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptPersonalDefaultsTests -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: pass if Task 4 is complete; fix service semantics before the view if it fails.

- [ ] **Step 3: Replace view-owned persistence with service state**

Keep existing SwiftUI `@State` fields, add `@State private var showFactoryRestoreConfirmation = false`, and add:

```swift
private var editorState: PromptEditorState {
    PromptEditorState(
        userPromptTemplate: user,
        modelName: activeModelName,
        temperature: temperature,
        maxTokens: maxTokens,
        reasoningEffort: normalizedReasoningEffort,
        mandate: mandate,
        enabledBlockKeys: orderedEnabledBlockKeys(),
        blockTexts: blockTexts
    )
}

private func apply(_ state: PromptEditorState) {
    user = state.userPromptTemplate
    modelName = state.modelName
    temperature = state.temperature
    maxTokens = state.maxTokens
    reasoningEffort = state.reasoningEffort ?? ""
    mandate = state.mandate
    enabledBlockKeys = Set(state.enabledBlockKeys)
    blockTexts = state.blockTexts
}
```

Replace `save()` persistence with:

```swift
private func load() {
    apply(PromptPersonalDefaultsService.liveState(template: template, role: role, blocks: blocks))
}

private func save() {
    PromptPersonalDefaultsService.saveAsPersonalDefault(
        editorState,
        template: template,
        role: role,
        blocks: blocks
    )
    savedNote = "Сохранено как мой дефолт · версия \(template.templateVersion)"
}
```

- [ ] **Step 4: Replace reset actions without implicit persistence**

Replace `bottomBar` with:

```swift
private var bottomBar: some View {
    HStack(spacing: 12) {
        Button("Сбросить к моему дефолту", action: restorePersonalDefault)
            .foregroundStyle(.secondary)
            .disabled(PromptPersonalDefaultsService.personalDefaultState(
                template: template, role: role, blocks: blocks
            ) == nil)
        Button("Вернуть стандарт приложения") {
            showFactoryRestoreConfirmation = true
        }
        .foregroundStyle(.secondary)
        Spacer()
        if let savedNote {
            Text(savedNote).font(.callout).foregroundStyle(.green)
        }
        Button {
            showSandbox = true
        } label: {
            Label("Песочница", systemImage: "play.fill")
        }
        Button("Сохранить", action: save)
            .buttonStyle(.borderedProminent)
    }
    .padding(14)
}
```

Add the two non-persisting loaders:

```swift
private func restorePersonalDefault() {
    guard let state = PromptPersonalDefaultsService.personalDefaultState(
        template: template,
        role: role,
        blocks: blocks
    ) else { return }
    apply(state)
    savedNote = "Загружен мой дефолт · нажмите «Сохранить»"
}

private func restoreFactoryDefault() {
    apply(PromptPersonalDefaultsService.factoryState(stage: stage, role: role, blocks: blocks))
    savedNote = "Загружен стандарт приложения · нажмите «Сохранить»"
}
```

Attach this dialog to the view after its existing sheet modifier, and delete the old `resetToDefault()` implementation:

```swift
.confirmationDialog(
    "Вернуть стандарт приложения?",
    isPresented: $showFactoryRestoreConfirmation,
    titleVisibility: .visible
) {
    Button("Загрузить стандарт приложения") { restoreFactoryDefault() }
    Button("Отмена", role: .cancel) {}
} message: {
    Text("Изменения пока попадут только в редактор. Если затем нажать «Сохранить», общая роль и контекстные блоки изменятся также в связанных этапах.")
}
```

Neither loader mutates SwiftData; only the existing explicit Save action calls `saveAsPersonalDefault`.

- [ ] **Step 5: Run service tests and compile UI**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptPersonalDefaultsTests -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: tests pass and UI compilation succeeds.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/Templates/StagePromptEditorView.swift SEOContentCreator/SEOContentCreatorTests/PromptPersonalDefaultsTests.swift
git commit -m "feat: make saved prompts personal defaults"
```

---

### Task 8: Integration, regression verification, and handoff

**Files:**
- Modify tests only if verification exposes a real missing assertion in the approved scope.
- Do not update `ai/changelog.md` or close `ai/current-task.md`; those belong to a later confirmed `task-finish` workflow.

**Interfaces:**
- Consumes: every prior task.
- Produces: verified implementation ready for user smoke testing and a `task-finish` proposal.

- [ ] **Step 1: Run focused suites together**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' \
  -only-testing:SEOContentCreatorTests/ReaderIntentTests \
  -only-testing:SEOContentCreatorTests/ReaderIntentAnalysisTests \
  -only-testing:SEOContentCreatorTests/PromptBuilderTests \
  -only-testing:SEOContentCreatorTests/StageTemplateDefaultsTests \
  -only-testing:SEOContentCreatorTests/PromptPersonalDefaultsTests \
  -only-testing:SEOContentCreatorTests/StagePromptIntentMigrationTests \
  -only-testing:SEOContentCreatorTests/StageTemplateSeederTests \
  -only-testing:SEOContentCreatorTests/TemplatesMigrationV3Tests \
  -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: `** TEST SUCCEEDED **` with all selected suites passing.

- [ ] **Step 2: Run the full unit-test target**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: `** TEST SUCCEEDED **`. If the known CLI runner hang recurs after completed suites, record the last completed suite and use focused tests plus `build-for-testing`; do not claim a clean full run.

- [ ] **Step 3: Run a compile check**

```bash
xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /private/tmp/SEOContentCreatorReaderIntentDerivedData
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Review final scope and protected files**

```bash
git diff --check
git diff --name-only 7f941de..HEAD
git status --short
```

Expected: no whitespace errors; no protected architecture files changed; controlled task memory unchanged after the design commit; only implementation/spec/plan files present.

- [ ] **Step 5: Manual smoke checklist**

```text
1. Existing topic without intent opens normally.
2. Preparation → Semantics opens the existing inspector tab.
3. Preparation → Reader Intent opens the editor.
4. Manual save persists and status becomes Ready.
5. AI generation produces an editable draft and Cancel preserves the saved card.
6. Changing accepted semantics changes status to Stale.
7. Structure warns when intent is missing but remains runnable.
8. Generated structure does not print the intent card.
9. Draft/metadata/SEO prompts receive the compact card; unrelated stages do not.
10. Saving a full stage state reports that it became the personal default.
11. Personal restore changes only unsaved editor fields until Save.
12. Factory restore warns about shared role/blocks and changes nothing until Save.
13. Reopening the app does not overwrite the personal default.
```

- [ ] **Step 6: Commit a verification-only test correction only if required**

If verification exposes a missing regression assertion while implementation behavior is already correct:

```bash
git add SEOContentCreator/SEOContentCreatorTests
git commit -m "test: cover reader intent integration regressions"
```

Otherwise do not create an empty commit.

- [ ] **Step 7: Report without closing the task**

Report changed components, exact test/build outcomes, remaining manual checks, migration risk, and task-memory state. Propose `task-finish`; do not run it without explicit confirmation.
