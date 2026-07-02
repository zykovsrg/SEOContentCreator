# Semantic Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first Semantic Agent workflow: mock keyword collection, OpenAI-based recommendations, manual review, and cannibalization checks against indexed `hadassah.moscow` pages.

**Architecture:** Add focused SwiftData models for semantic keyword decisions and published site pages, keep the legacy `Topic.semantics` field during the migration window, and make prompt rendering prefer the new records with a safe legacy fallback. Keep external work user-triggered: site refresh is a button, OpenAI analysis is a button, and agent recommendations are saved as pending user decisions.

**Tech Stack:** Swift, SwiftUI, SwiftData, URLSession, existing `OpenAIClient`, Swift Testing, macOS app target with Xcode synchronized source groups.

---

## File Map

- Create `SEOContentCreator/SEOContentCreator/Models/SemanticKeyword.swift`
  - Holds keyword decision records and user-facing enum labels.
- Create `SEOContentCreator/SEOContentCreator/Models/PublishedSitePage.swift`
  - Holds indexed public page summaries for `hadassah.moscow`.
- Modify `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
  - Add relationship to `SemanticKeyword`; keep legacy `semantics: [String]`.
- Modify `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`
  - Register new SwiftData models in the app container.
- Create `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordBackfill.swift`
  - Converts legacy strings into accepted records without clearing legacy data.
- Create `SEOContentCreator/SEOContentCreator/Logic/SemanticPromptRenderer.swift`
  - Produces the text for `{{семантика}}`.
- Modify `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`
  - Use `SemanticPromptRenderer`.
- Create `SEOContentCreator/SEOContentCreator/Logic/SemanticMockKeywordCollector.swift`
  - Deterministic mock candidate generator for the first version.
- Create `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentResponseParser.swift`
  - Strict JSON parser for OpenAI output.
- Create `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift`
  - Builds prompts and streams OpenAI output through the existing client contract.
- Create `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordMerger.swift`
  - Upserts agent results into topic keywords as pending decisions.
- Create `SEOContentCreator/SEOContentCreator/Logic/SitePageHTMLParser.swift`
  - Extracts title, description, H1, and H2 from public HTML.
- Create `SEOContentCreator/SEOContentCreator/Logic/SitePageIndexer.swift`
  - Refreshes published page summaries from `hadassah.moscow`.
- Modify `SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift`
  - Replace line editor with the decision table, filters, and actions.
- Create `SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift`
  - Runs mock collection and OpenAI analysis, then saves pending results.
- Add tests under `SEOContentCreator/SEOContentCreatorTests/`.

The Xcode project uses file-system synchronized groups, so adding Swift files under the existing target folders should not require editing `SEOContentCreator.xcodeproj/project.pbxproj`.

## Test Command

Use this command after each task that changes Swift code:

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS'
```

Expected final result: `** TEST SUCCEEDED **`.

---

### Task 1: Add SemanticKeyword Model And Backfill

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/SemanticKeyword.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordBackfill.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticKeywordBackfillTests.swift`

- [ ] **Step 1: Write failing tests for legacy backfill**

Create `SEOContentCreator/SEOContentCreatorTests/SemanticKeywordBackfillTests.swift`:

```swift
import Testing
import SwiftData
@testable import SEOContentCreator

struct SemanticKeywordBackfillTests {
    @Test func backfillsLegacySemanticsAsAcceptedKeywords() throws {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        topic.semantics = ["рак простаты лечение", "лучевая терапия простаты"]

        SemanticKeywordBackfill.backfill(topic)

        #expect(topic.semanticKeywords.count == 2)
        #expect(topic.semanticKeywords.map(\.text).contains("рак простаты лечение"))
        #expect(topic.semanticKeywords.allSatisfy { $0.userDecision == .accepted })
        #expect(topic.semanticKeywords.allSatisfy { $0.agentRecommendation == .none })
        #expect(topic.semantics == ["рак простаты лечение", "лучевая терапия простаты"])
    }

    @Test func backfillDoesNotDuplicateExistingKeyword() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        topic.semantics = ["рак простаты лечение"]
        let existing = SemanticKeyword(text: "рак простаты лечение", userDecision: .accepted)
        existing.topic = topic
        topic.semanticKeywords = [existing]

        SemanticKeywordBackfill.backfill(topic)

        #expect(topic.semanticKeywords.count == 1)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticKeywordBackfillTests
```

Expected: build fails because `SemanticKeyword`, `semanticKeywords`, and `SemanticKeywordBackfill` do not exist.

- [ ] **Step 3: Add the model and Topic relationship**

Create `SEOContentCreator/SEOContentCreator/Models/SemanticKeyword.swift`:

```swift
import Foundation
import SwiftData

enum SemanticAgentRecommendation: String, Codable, CaseIterable {
    case include
    case exclude
    case none

    var label: String {
        switch self {
        case .include: return "Включить"
        case .exclude: return "Не включать"
        case .none: return "Нет рекомендации"
        }
    }
}

enum SemanticUserDecision: String, Codable, CaseIterable {
    case pending
    case accepted
    case rejected
    case required

    var label: String {
        switch self {
        case .pending: return "Ожидает решения"
        case .accepted: return "Принято"
        case .rejected: return "Отклонено"
        case .required: return "Обязательно"
        }
    }
}

enum SemanticReasonCategory: String, Codable, CaseIterable {
    case none
    case junk
    case offTopic
    case cannibalization
    case lowQuality
    case tooBroad
    case wrongIntent
    case other

    var label: String {
        switch self {
        case .none: return "Нет"
        case .junk: return "Мусор"
        case .offTopic: return "Не по теме"
        case .cannibalization: return "Каннибализация"
        case .lowQuality: return "Низкое качество"
        case .tooBroad: return "Слишком общий"
        case .wrongIntent: return "Не тот интент"
        case .other: return "Другое"
        }
    }
}

enum SemanticCannibalizationRisk: String, Codable, CaseIterable {
    case none
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .none: return "Нет"
        case .low: return "Низкий"
        case .medium: return "Средний"
        case .high: return "Высокий"
        }
    }
}

@Model
final class SemanticKeyword {
    var uuid: UUID
    var text: String
    var frequency: Int?
    var agentRecommendationRaw: String
    var userDecisionRaw: String
    var reasonCategoryRaw: String
    var explanation: String
    var cannibalizationRiskRaw: String
    var cannibalizationURL: String?
    var cannibalizationTitle: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship var topic: Topic?

    init(
        text: String,
        frequency: Int? = nil,
        agentRecommendation: SemanticAgentRecommendation = .none,
        userDecision: SemanticUserDecision = .pending,
        reasonCategory: SemanticReasonCategory = .none,
        explanation: String = "",
        cannibalizationRisk: SemanticCannibalizationRisk = .none,
        cannibalizationURL: String? = nil,
        cannibalizationTitle: String? = nil
    ) {
        self.uuid = UUID()
        self.text = text
        self.frequency = frequency
        self.agentRecommendationRaw = agentRecommendation.rawValue
        self.userDecisionRaw = userDecision.rawValue
        self.reasonCategoryRaw = reasonCategory.rawValue
        self.explanation = explanation
        self.cannibalizationRiskRaw = cannibalizationRisk.rawValue
        self.cannibalizationURL = cannibalizationURL
        self.cannibalizationTitle = cannibalizationTitle
        self.createdAt = .now
        self.updatedAt = .now
    }

    var agentRecommendation: SemanticAgentRecommendation {
        get { SemanticAgentRecommendation(rawValue: agentRecommendationRaw) ?? .none }
        set { agentRecommendationRaw = newValue.rawValue; updatedAt = .now }
    }

    var userDecision: SemanticUserDecision {
        get { SemanticUserDecision(rawValue: userDecisionRaw) ?? .pending }
        set { userDecisionRaw = newValue.rawValue; updatedAt = .now }
    }

    var reasonCategory: SemanticReasonCategory {
        get { SemanticReasonCategory(rawValue: reasonCategoryRaw) ?? .none }
        set { reasonCategoryRaw = newValue.rawValue; updatedAt = .now }
    }

    var cannibalizationRisk: SemanticCannibalizationRisk {
        get { SemanticCannibalizationRisk(rawValue: cannibalizationRiskRaw) ?? .none }
        set { cannibalizationRiskRaw = newValue.rawValue; updatedAt = .now }
    }
}
```

Modify `SEOContentCreator/SEOContentCreator/Models/Topic.swift`:

```swift
@Relationship(deleteRule: .cascade, inverse: \SemanticKeyword.topic)
var semanticKeywords: [SemanticKeyword] = []
```

Initialize it in `init`:

```swift
self.semanticKeywords = []
```

Modify `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift` by adding `SemanticKeyword.self` to the `.modelContainer(for:)` list.

- [ ] **Step 4: Add backfill helper**

Create `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordBackfill.swift`:

```swift
import Foundation

enum SemanticKeywordBackfill {
    static func backfill(_ topic: Topic) {
        let existing = Set(topic.semanticKeywords.map { normalize($0.text) })
        let additions = topic.semantics
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !existing.contains(normalize($0)) }
            .map { SemanticKeyword(text: $0, agentRecommendation: .none, userDecision: .accepted) }

        for keyword in additions {
            keyword.topic = topic
        }
        topic.semanticKeywords.append(contentsOf: additions)
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticKeywordBackfillTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/Topic.swift SEOContentCreator/SEOContentCreator/Models/SemanticKeyword.swift SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordBackfill.swift SEOContentCreator/SEOContentCreatorTests/SemanticKeywordBackfillTests.swift
git commit -m "Add semantic keyword model"
```

---

### Task 2: Render Prompt Semantics From Decisions

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticPromptRenderer.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticPromptRendererTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift`

- [ ] **Step 1: Write failing renderer tests**

Create `SEOContentCreator/SEOContentCreatorTests/SemanticPromptRendererTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct SemanticPromptRendererTests {
    @Test func rendersAcceptedAndRequiredOnly() {
        let topic = Topic(title: "Тест", articleType: .info)
        topic.semanticKeywords = [
            SemanticKeyword(text: "принятый запрос", userDecision: .accepted),
            SemanticKeyword(text: "обязательный запрос", userDecision: .required),
            SemanticKeyword(text: "ожидающий запрос", userDecision: .pending),
            SemanticKeyword(text: "отклонённый запрос", userDecision: .rejected)
        ]

        let rendered = SemanticPromptRenderer.render(topic: topic)

        #expect(rendered.contains("принятый запрос"))
        #expect(rendered.contains("обязательный запрос"))
        #expect(rendered.contains("обязательный"))
        #expect(!rendered.contains("ожидающий запрос"))
        #expect(!rendered.contains("отклонённый запрос"))
    }

    @Test func fallsBackToLegacySemanticsWhenNoKeywordRecordsExist() {
        let topic = Topic(title: "Тест", articleType: .info)
        topic.semantics = ["старый запрос"]

        #expect(SemanticPromptRenderer.render(topic: topic) == "старый запрос")
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticPromptRendererTests
```

Expected: build fails because `SemanticPromptRenderer` does not exist.

- [ ] **Step 3: Implement renderer**

Create `SEOContentCreator/SEOContentCreator/Logic/SemanticPromptRenderer.swift`:

```swift
import Foundation

enum SemanticPromptRenderer {
    static func render(topic: Topic) -> String {
        let records = topic.semanticKeywords
            .filter { $0.userDecision == .accepted || $0.userDecision == .required }
            .sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }

        if records.isEmpty {
            return topic.semantics.joined(separator: "\n")
        }

        return records.map { keyword in
            if keyword.userDecision == .required {
                return "\(keyword.text) (обязательный запрос)"
            }
            return keyword.text
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Wire PromptBuilder**

Modify `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`:

```swift
let semantics = SemanticPromptRenderer.render(topic: topic)
```

Replace the current `topic.semantics.joined(separator: "\n")` line.

- [ ] **Step 5: Update existing prompt test**

In `SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift`, add this test:

```swift
@Test func semanticKeywordDecisionsDriveSemanticsPlaceholder() {
    let t = StageTemplate(stage: .semanticsInText, systemPrompt: "x",
                          userPromptTemplate: "Запросы:\n{{семантика}}")
    let topic = Topic(title: "T", articleType: .info)
    topic.semanticKeywords = [
        SemanticKeyword(text: "принятый", userDecision: .accepted),
        SemanticKeyword(text: "обязательный", userDecision: .required),
        SemanticKeyword(text: "отклонённый", userDecision: .rejected)
    ]

    let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)

    #expect(result.user.contains("принятый"))
    #expect(result.user.contains("обязательный"))
    #expect(!result.user.contains("отклонённый"))
}
```

- [ ] **Step 6: Run tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticPromptRendererTests -only-testing:SEOContentCreatorTests/PromptBuilderTests
```

Expected: tests pass.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticPromptRenderer.swift SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift SEOContentCreator/SEOContentCreatorTests/SemanticPromptRendererTests.swift SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift
git commit -m "Render accepted semantic keywords in prompts"
```

---

### Task 3: Add Published Site Page Model And HTML Parser

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/PublishedSitePage.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/SitePageHTMLParser.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SitePageHTMLParserTests.swift`

- [ ] **Step 1: Write parser tests**

Create `SEOContentCreator/SEOContentCreatorTests/SitePageHTMLParserTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct SitePageHTMLParserTests {
    @Test func extractsTitleDescriptionAndHeadings() {
        let html = """
        <html><head>
        <title>Лечение рака простаты</title>
        <meta name="description" content="Описание страницы">
        </head><body>
        <h1>Рак простаты</h1>
        <h2>Диагностика</h2>
        <h2>Лечение</h2>
        </body></html>
        """

        let parsed = SitePageHTMLParser.parse(html: html)

        #expect(parsed.title == "Лечение рака простаты")
        #expect(parsed.metaDescription == "Описание страницы")
        #expect(parsed.h1 == ["Рак простаты"])
        #expect(parsed.h2 == ["Диагностика", "Лечение"])
    }
}
```

- [ ] **Step 2: Run test and verify it fails**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SitePageHTMLParserTests
```

Expected: build fails because parser and model do not exist.

- [ ] **Step 3: Add model**

Create `SEOContentCreator/SEOContentCreator/Models/PublishedSitePage.swift`:

```swift
import Foundation
import SwiftData

@Model
final class PublishedSitePage {
    var uuid: UUID
    var url: String
    var title: String
    var metaDescription: String
    var h1: [String]
    var h2: [String]
    var siteHost: String
    var indexedAt: Date

    init(
        url: String,
        title: String = "",
        metaDescription: String = "",
        h1: [String] = [],
        h2: [String] = [],
        siteHost: String = "hadassah.moscow",
        indexedAt: Date = .now
    ) {
        self.uuid = UUID()
        self.url = url
        self.title = title
        self.metaDescription = metaDescription
        self.h1 = h1
        self.h2 = h2
        self.siteHost = siteHost
        self.indexedAt = indexedAt
    }

    var summaryForAgent: String {
        [
            "URL: \(url)",
            "Title: \(title)",
            "Description: \(metaDescription)",
            "H1: \(h1.joined(separator: " | "))",
            "H2: \(h2.joined(separator: " | "))"
        ].joined(separator: "\n")
    }
}
```

Modify `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift` by adding `PublishedSitePage.self` to the model container.

- [ ] **Step 4: Add parser**

Create `SEOContentCreator/SEOContentCreator/Logic/SitePageHTMLParser.swift`:

```swift
import Foundation

struct SitePageHTMLSummary: Equatable {
    var title: String
    var metaDescription: String
    var h1: [String]
    var h2: [String]
}

enum SitePageHTMLParser {
    static func parse(html: String) -> SitePageHTMLSummary {
        SitePageHTMLSummary(
            title: firstMatch(html, pattern: #"<title[^>]*>(.*?)</title>"#),
            metaDescription: firstMatch(html, pattern: #"<meta\s+[^>]*name=["']description["'][^>]*content=["']([^"']*)["'][^>]*>"#),
            h1: allMatches(html, pattern: #"<h1[^>]*>(.*?)</h1>"#),
            h2: allMatches(html, pattern: #"<h2[^>]*>(.*?)</h2>"#)
        )
    }

    private static func firstMatch(_ text: String, pattern: String) -> String {
        allMatches(text, pattern: pattern).first ?? ""
    }

    private static func allMatches(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return clean(ns.substring(with: match.range(at: 1)))
        }.filter { !$0.isEmpty }
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 5: Run parser tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SitePageHTMLParserTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/PublishedSitePage.swift SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift SEOContentCreator/SEOContentCreator/Logic/SitePageHTMLParser.swift SEOContentCreator/SEOContentCreatorTests/SitePageHTMLParserTests.swift
git commit -m "Add published page index model"
```

---

### Task 4: Add Mock Collector And Agent Response Parser

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticMockKeywordCollector.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentResponseParser.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticAgentResponseParserTests.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticMockKeywordCollectorTests.swift`

- [ ] **Step 1: Write parser and collector tests**

Create `SEOContentCreator/SEOContentCreatorTests/SemanticAgentResponseParserTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct SemanticAgentResponseParserTests {
    @Test func parsesValidAgentJSON() throws {
        let json = """
        {
          "keywords": [
            {
              "query": "лечение рака простаты",
              "frequency": 120,
              "recommendation": "exclude",
              "reasonCategory": "cannibalization",
              "explanation": "Похоже на существующую страницу.",
              "cannibalizationRisk": "high",
              "cannibalizationURL": "https://hadassah.moscow/prostate",
              "cannibalizationTitle": "Рак простаты"
            }
          ]
        }
        """

        let parsed = try SemanticAgentResponseParser.parse(json)

        #expect(parsed.count == 1)
        #expect(parsed[0].query == "лечение рака простаты")
        #expect(parsed[0].frequency == 120)
        #expect(parsed[0].recommendation == .exclude)
        #expect(parsed[0].reasonCategory == .cannibalization)
        #expect(parsed[0].cannibalizationRisk == .high)
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: SemanticAgentResponseParser.ParserError.badResponse) {
            try SemanticAgentResponseParser.parse("{bad")
        }
    }
}
```

Create `SEOContentCreator/SEOContentCreatorTests/SemanticMockKeywordCollectorTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct SemanticMockKeywordCollectorTests {
    @Test func returnsStableQueriesForTopic() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)

        let first = SemanticMockKeywordCollector.collect(for: topic)
        let second = SemanticMockKeywordCollector.collect(for: topic)

        #expect(first == second)
        #expect(first.contains("рак простаты лечение"))
        #expect(first.contains("рак простаты цена"))
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticAgentResponseParserTests -only-testing:SEOContentCreatorTests/SemanticMockKeywordCollectorTests
```

Expected: build fails because parser and collector do not exist.

- [ ] **Step 3: Add response parser**

Create `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentResponseParser.swift`:

```swift
import Foundation

struct SemanticAgentKeywordResult: Equatable {
    var query: String
    var frequency: Int?
    var recommendation: SemanticAgentRecommendation
    var reasonCategory: SemanticReasonCategory
    var explanation: String
    var cannibalizationRisk: SemanticCannibalizationRisk
    var cannibalizationURL: String?
    var cannibalizationTitle: String?
}

enum SemanticAgentResponseParser {
    enum ParserError: Error, Equatable {
        case badResponse
    }

    private struct Envelope: Decodable {
        var keywords: [Item]
    }

    private struct Item: Decodable {
        var query: String
        var frequency: Int?
        var recommendation: String
        var reasonCategory: String
        var explanation: String
        var cannibalizationRisk: String
        var cannibalizationURL: String?
        var cannibalizationTitle: String?
    }

    static func parse(_ text: String) throws -> [SemanticAgentKeywordResult] {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ParserError.badResponse
        }

        return envelope.keywords.map { item in
            SemanticAgentKeywordResult(
                query: item.query.trimmingCharacters(in: .whitespacesAndNewlines),
                frequency: item.frequency,
                recommendation: SemanticAgentRecommendation(rawValue: item.recommendation) ?? .none,
                reasonCategory: SemanticReasonCategory(rawValue: item.reasonCategory) ?? .other,
                explanation: item.explanation,
                cannibalizationRisk: SemanticCannibalizationRisk(rawValue: item.cannibalizationRisk) ?? .none,
                cannibalizationURL: item.cannibalizationURL,
                cannibalizationTitle: item.cannibalizationTitle
            )
        }.filter { !$0.query.isEmpty }
    }
}
```

- [ ] **Step 4: Add mock collector**

Create `SEOContentCreator/SEOContentCreator/Logic/SemanticMockKeywordCollector.swift`:

```swift
import Foundation

enum SemanticMockKeywordCollector {
    static func collect(for topic: Topic) -> [String] {
        let base = topic.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !base.isEmpty else { return [] }

        return [
            "\(base) лечение",
            "\(base) симптомы",
            "\(base) диагностика",
            "\(base) цена",
            "\(base) отзывы",
            "\(base) форум",
            "\(base) hadassah",
            "\(base) операция",
            "\(base) лучевая терапия",
            "\(base) врач"
        ]
    }
}
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticAgentResponseParserTests -only-testing:SEOContentCreatorTests/SemanticMockKeywordCollectorTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticAgentResponseParser.swift SEOContentCreator/SEOContentCreator/Logic/SemanticMockKeywordCollector.swift SEOContentCreator/SEOContentCreatorTests/SemanticAgentResponseParserTests.swift SEOContentCreator/SEOContentCreatorTests/SemanticMockKeywordCollectorTests.swift
git commit -m "Parse semantic agent responses"
```

---

### Task 5: Add Semantic Agent Analyzer

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticAgentAnalyzerTests.swift`

- [ ] **Step 1: Write analyzer tests**

Create `SEOContentCreator/SEOContentCreatorTests/SemanticAgentAnalyzerTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

@MainActor
struct SemanticAgentAnalyzerTests {
    @Test func sendsTopicQueriesAndPagesToStreamProvider() async throws {
        var capturedUser = ""
        let analyzer = SemanticAgentAnalyzer(
            streamProvider: { _, _, user, _, _, _, _ in
                capturedUser = user
                return AsyncThrowingStream { continuation in
                    continuation.yield(.token("""
                    {"keywords":[{"query":"рак простаты лечение","frequency":10,"recommendation":"include","reasonCategory":"none","explanation":"Подходит теме","cannibalizationRisk":"none"}]}
                    """))
                    continuation.finish()
                }
            },
            keyProvider: { "sk-test" },
            model: "gpt-4.1"
        )
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let page = PublishedSitePage(url: "https://hadassah.moscow/prostate", title: "Рак простаты")

        let result = try await analyzer.analyze(topic: topic, queries: ["рак простаты лечение"], pages: [page])

        #expect(result.count == 1)
        #expect(capturedUser.contains("Рак простаты"))
        #expect(capturedUser.contains("рак простаты лечение"))
        #expect(capturedUser.contains("https://hadassah.moscow/prostate"))
    }
}
```

- [ ] **Step 2: Run test and verify it fails**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticAgentAnalyzerTests
```

Expected: build fails because analyzer does not exist.

- [ ] **Step 3: Implement analyzer**

Create `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift`:

```swift
import Foundation

@MainActor
struct SemanticAgentAnalyzer {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = StageExecutor.KeyProvider

    enum AnalyzerError: Error, LocalizedError {
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse: return "Агент не вернул результат. Попробуйте ещё раз."
            }
        }
    }

    let streamProvider: StreamProvider
    let keyProvider: KeyProvider
    let model: String

    static func live(model: String) -> SemanticAgentAnalyzer {
        SemanticAgentAnalyzer(
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

    func analyze(topic: Topic, queries: [String], pages: [PublishedSitePage]) async throws -> [SemanticAgentKeywordResult] {
        let key = try keyProvider()
        var collected = ""
        for try await event in streamProvider(
            key,
            systemPrompt,
            userPrompt(topic: topic, queries: queries, pages: pages),
            model,
            0.2,
            4000,
            nil
        ) {
            if case .token(let token) = event {
                collected += token
            }
        }
        guard !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyzerError.emptyResponse
        }
        return try SemanticAgentResponseParser.parse(collected)
    }

    private var systemPrompt: String {
        """
        Ты SEO-аналитик медицинского сайта. Верни только JSON без Markdown.
        Решай, какие запросы стоит включить в семантику темы, а какие не стоит.
        Учитывай мусорные запросы, неподходящий интент и каннибализацию с опубликованными страницами.
        """
    }

    private func userPrompt(topic: Topic, queries: [String], pages: [PublishedSitePage]) -> String {
        """
        Тема: \(topic.title)
        Тип статьи: \(topic.articleType.title)

        Кандидаты:
        \(queries.map { "- \($0)" }.joined(separator: "\n"))

        Опубликованные страницы сайта:
        \(pages.map(\.summaryForAgent).joined(separator: "\n\n---\n\n"))

        Верни JSON:
        {"keywords":[{"query":"...","frequency":null,"recommendation":"include|exclude","reasonCategory":"none|junk|offTopic|cannibalization|lowQuality|tooBroad|wrongIntent|other","explanation":"короткая причина","cannibalizationRisk":"none|low|medium|high","cannibalizationURL":null,"cannibalizationTitle":null}]}
        """
    }
}
```

- [ ] **Step 4: Run analyzer tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticAgentAnalyzerTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift SEOContentCreator/SEOContentCreatorTests/SemanticAgentAnalyzerTests.swift
git commit -m "Add semantic agent analyzer"
```

---

### Task 6: Add Site Page Indexer

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SitePageIndexer.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SitePageIndexerTests.swift`

- [ ] **Step 1: Write indexer tests**

Create `SEOContentCreator/SEOContentCreatorTests/SitePageIndexerTests.swift`:

```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct SitePageIndexerTests {
    @Test func extractsSitemapLocations() throws {
        let xml = """
        <urlset>
          <url><loc>https://hadassah.moscow/a</loc></url>
          <url><loc>https://hadassah.moscow/b</loc></url>
        </urlset>
        """

        let urls = SitePageIndexer.extractURLs(fromSitemapXML: xml)

        #expect(urls.map(\.absoluteString) == ["https://hadassah.moscow/a", "https://hadassah.moscow/b"])
    }

    @Test func keepsOnlyHadassahHTMLURLs() {
        let urls = [
            URL(string: "https://hadassah.moscow/a")!,
            URL(string: "https://example.com/b")!,
            URL(string: "https://hadassah.moscow/file.pdf")!
        ]

        let filtered = SitePageIndexer.filterPageURLs(urls)

        #expect(filtered.map(\.absoluteString) == ["https://hadassah.moscow/a"])
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SitePageIndexerTests
```

Expected: build fails because `SitePageIndexer` does not exist.

- [ ] **Step 3: Implement indexer core**

Create `SEOContentCreator/SEOContentCreator/Logic/SitePageIndexer.swift`:

```swift
import Foundation
import SwiftData

struct SitePageIndexer {
    enum IndexerError: Error, LocalizedError {
        case sitemapUnavailable

        var errorDescription: String? {
            switch self {
            case .sitemapUnavailable: return "Не удалось получить sitemap сайта."
            }
        }
    }

    let session: URLSession
    let sitemapURL: URL

    init(
        session: URLSession = .shared,
        sitemapURL: URL = URL(string: "https://hadassah.moscow/sitemap.xml")!
    ) {
        self.session = session
        self.sitemapURL = sitemapURL
    }

    static func extractURLs(fromSitemapXML xml: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"<loc>(.*?)</loc>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return URL(string: ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func filterPageURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            url.host == "hadassah.moscow"
                && !url.path.lowercased().hasSuffix(".pdf")
                && !url.path.lowercased().hasSuffix(".jpg")
                && !url.path.lowercased().hasSuffix(".png")
                && !url.path.lowercased().hasSuffix(".webp")
        }
    }

    func fetchPages(limit: Int = 200) async throws -> [PublishedSitePage] {
        let (sitemapData, response) = try await session.data(from: sitemapURL)
        guard (response as? HTTPURLResponse)?.statusCode.map({ 200...299 ~= $0 }) ?? false,
              let xml = String(data: sitemapData, encoding: .utf8) else {
            throw IndexerError.sitemapUnavailable
        }

        let urls = Self.filterPageURLs(Self.extractURLs(fromSitemapXML: xml)).prefix(limit)
        var pages: [PublishedSitePage] = []
        for url in urls {
            do {
                let (data, response) = try await session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode.map({ 200...299 ~= $0 }) ?? false,
                      let html = String(data: data, encoding: .utf8) else {
                    continue
                }
                let summary = SitePageHTMLParser.parse(html: html)
                pages.append(PublishedSitePage(
                    url: url.absoluteString,
                    title: summary.title,
                    metaDescription: summary.metaDescription,
                    h1: summary.h1,
                    h2: summary.h2
                ))
            } catch {
                continue
            }
        }
        return pages
    }
}
```

- [ ] **Step 4: Run indexer tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SitePageIndexerTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SitePageIndexer.swift SEOContentCreator/SEOContentCreatorTests/SitePageIndexerTests.swift
git commit -m "Add published site page indexer"
```

---

### Task 7: Merge Agent Results Into Topic Keywords

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordMerger.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SemanticKeywordMergerTests.swift`

- [ ] **Step 1: Write merger tests**

Create `SEOContentCreator/SEOContentCreatorTests/SemanticKeywordMergerTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct SemanticKeywordMergerTests {
    @Test func savesAgentResultsAsPendingDecisions() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let result = SemanticAgentKeywordResult(
            query: "рак простаты лечение",
            frequency: 120,
            recommendation: .include,
            reasonCategory: .none,
            explanation: "Подходит теме",
            cannibalizationRisk: .none,
            cannibalizationURL: nil,
            cannibalizationTitle: nil
        )

        SemanticKeywordMerger.merge([result], into: topic)

        #expect(topic.semanticKeywords.count == 1)
        #expect(topic.semanticKeywords[0].userDecision == .pending)
        #expect(topic.semanticKeywords[0].agentRecommendation == .include)
        #expect(topic.semanticKeywords[0].frequency == 120)
    }

    @Test func updatesExistingKeywordInsteadOfDuplicating() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let existing = SemanticKeyword(text: "рак простаты лечение", userDecision: .accepted)
        existing.topic = topic
        topic.semanticKeywords = [existing]
        let result = SemanticAgentKeywordResult(
            query: " Рак Простаты Лечение ",
            frequency: 200,
            recommendation: .exclude,
            reasonCategory: .cannibalization,
            explanation: "Есть похожая страница",
            cannibalizationRisk: .high,
            cannibalizationURL: "https://hadassah.moscow/prostate",
            cannibalizationTitle: "Рак простаты"
        )

        SemanticKeywordMerger.merge([result], into: topic)

        #expect(topic.semanticKeywords.count == 1)
        #expect(topic.semanticKeywords[0].userDecision == .accepted)
        #expect(topic.semanticKeywords[0].agentRecommendation == .exclude)
        #expect(topic.semanticKeywords[0].cannibalizationRisk == .high)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticKeywordMergerTests
```

Expected: build fails because merger does not exist.

- [ ] **Step 3: Implement merger**

Create `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordMerger.swift`:

```swift
import Foundation

enum SemanticKeywordMerger {
    static func merge(_ results: [SemanticAgentKeywordResult], into topic: Topic) {
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
                existing.updatedAt = .now
            } else {
                let keyword = SemanticKeyword(
                    text: result.query.trimmingCharacters(in: .whitespacesAndNewlines),
                    frequency: result.frequency,
                    agentRecommendation: result.recommendation,
                    userDecision: .pending,
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

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
```

- [ ] **Step 4: Run merger tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticKeywordMergerTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordMerger.swift SEOContentCreator/SEOContentCreatorTests/SemanticKeywordMergerTests.swift
git commit -m "Merge semantic agent results"
```

---

### Task 8: Build Semantics Table UI

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift`
- Test manually: Semantics sheet display and actions.

- [ ] **Step 1: Replace editor state with table state**

In `SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift`, keep `@Bindable var topic: Topic`, add:

```swift
@State private var filter: SemanticFilter = .all
@State private var selectedIDs: Set<UUID> = []
@State private var showAgent = false
@State private var isRefreshingPages = false
@State private var message: String?

private enum SemanticFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case accepted
    case rejected
    case include
    case exclude

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Все"
        case .pending: return "Ожидают"
        case .accepted: return "Принятые"
        case .rejected: return "Отклонённые"
        case .include: return "Рекомендуется"
        case .exclude: return "Не рекомендуется"
        }
    }
}
```

- [ ] **Step 2: Add filtered keyword helper**

Add inside `SemanticsEditorSheet`:

```swift
private var visibleKeywords: [SemanticKeyword] {
    topic.semanticKeywords.filter { keyword in
        switch filter {
        case .all: return true
        case .pending: return keyword.userDecision == .pending
        case .accepted: return keyword.userDecision == .accepted
        case .rejected: return keyword.userDecision == .rejected
        case .include: return keyword.agentRecommendation == .include
        case .exclude: return keyword.agentRecommendation == .exclude
        }
    }.sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }
}
```

- [ ] **Step 3: Replace body with table layout**

Use this structure:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("Семантика").font(.headline)
            Spacer()
            Picker("Фильтр", selection: $filter) {
                ForEach(SemanticFilter.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.menu)
            Button("Обновить страницы сайта") { refreshSitePages() }
                .disabled(isRefreshingPages)
            Button("Сбор агентом") { showAgent = true }
        }

        if let message {
            Text(message).font(.callout).foregroundStyle(.secondary)
        }

        Table(visibleKeywords, selection: $selectedIDs) {
            TableColumn("Запрос") { Text($0.text) }
            TableColumn("Частотность") { Text($0.frequency.map(String.init) ?? "—") }
            TableColumn("Рекомендация") { Text($0.agentRecommendation.label) }
            TableColumn("Решение") { Text($0.userDecision.label) }
            TableColumn("Причина") { Text($0.reasonCategory.label) }
            TableColumn("Риск") { Text($0.cannibalizationRisk.label) }
            TableColumn("Страница") { keyword in
                Text(keyword.cannibalizationTitle ?? keyword.cannibalizationURL ?? "—")
                    .lineLimit(1)
            }
        }

        HStack {
            Button("Принять выбранные") { setDecision(.accepted) }
                .disabled(selectedIDs.isEmpty)
            Button("Отклонить выбранные") { setDecision(.rejected) }
                .disabled(selectedIDs.isEmpty)
            Button("Сделать обязательными") { setDecision(.required) }
                .disabled(selectedIDs.isEmpty)
            Spacer()
            Button("Закрыть") { dismiss() }
        }
    }
    .padding()
    .frame(width: 980, height: 560)
    .onAppear {
        SemanticKeywordBackfill.backfill(topic)
    }
    .sheet(isPresented: $showAgent) {
        SemanticAgentSheet(topic: topic)
    }
}
```

- [ ] **Step 4: Add decision helper and refresh stub**

Add:

```swift
private func setDecision(_ decision: SemanticUserDecision) {
    for keyword in topic.semanticKeywords where selectedIDs.contains(keyword.uuid) {
        keyword.userDecision = decision
    }
    topic.updatedAt = .now
}

private func refreshSitePages() {
    message = "Обновление индекса сайта будет подключено в следующем шаге."
}
```

Task 10 replaces the refresh stub with real indexing.

- [ ] **Step 5: Build**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticPromptRendererTests
```

Expected: build succeeds and selected tests pass.

- [ ] **Step 6: Manual check**

Open the app, open a topic, open Semantics. Confirm the sheet shows a table and the buttons are visible. Existing legacy strings should appear after the sheet opens.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift
git commit -m "Replace semantics editor with decision table"
```

---

### Task 9: Build Semantic Agent Sheet

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift` if compile fixes are needed.

- [ ] **Step 1: Create the sheet skeleton**

Create `SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift`:

```swift
import SwiftUI
import SwiftData

struct SemanticAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic
    @Query(filter: #Predicate<PublishedSitePage> { $0.siteHost == "hadassah.moscow" })
    private var pages: [PublishedSitePage]

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @State private var candidates: [String] = []
    @State private var results: [SemanticAgentKeywordResult] = []
    @State private var isRunning = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сбор семантики агентом").font(.headline)
            Text(topic.title).foregroundStyle(.secondary)

            if pages.isEmpty {
                Text("Индекс страниц сайта пустой. Проверка каннибализации будет неполной.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Сгенерировать тестовые запросы") { generateCandidates() }
                Button("Проанализировать через OpenAI") { analyze() }
                    .disabled(candidates.isEmpty || isRunning)
                Spacer()
                if isRunning { ProgressView() }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            HSplitView {
                candidateList
                resultList
            }

            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить в семантику") { saveResults() }
                    .disabled(results.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 900, height: 560)
    }

    private var candidateList: some View {
        List(candidates, id: \.self) { query in
            Text(query)
        }
        .frame(minWidth: 280)
    }

    private var resultList: some View {
        List(results, id: \.query) { result in
            VStack(alignment: .leading, spacing: 4) {
                Text(result.query).font(.headline)
                Text(result.recommendation.label)
                Text(result.reasonCategory.label)
                Text(result.explanation).foregroundStyle(.secondary)
                if result.cannibalizationRisk != .none {
                    Text("Риск: \(result.cannibalizationRisk.label)")
                    Text(result.cannibalizationTitle ?? result.cannibalizationURL ?? "")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minWidth: 420)
    }
}
```

- [ ] **Step 2: Add actions**

Add these methods inside `SemanticAgentSheet`:

```swift
private func generateCandidates() {
    candidates = SemanticMockKeywordCollector.collect(for: topic)
    results = []
    message = "Тестовые запросы готовы."
}

private func analyze() {
    isRunning = true
    message = nil
    Task {
        do {
            let analyzer = SemanticAgentAnalyzer.live(model: model)
            let analyzed = try await analyzer.analyze(topic: topic, queries: candidates, pages: pages)
            results = analyzed
            message = "Анализ завершён."
        } catch {
            message = error.localizedDescription
        }
        isRunning = false
    }
}

private func saveResults() {
    SemanticKeywordMerger.merge(results, into: topic)
    try? context.save()
    dismiss()
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticAgentAnalyzerTests
```

Expected: build succeeds and analyzer tests pass.

- [ ] **Step 4: Manual check**

Open Semantics, click Semantic Agent, generate mock queries, verify candidate list appears. If no OpenAI key is configured, clicking analysis should show the existing keychain error message.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift
git commit -m "Add semantic agent sheet"
```

---

### Task 10: Wire Manual Site Index Refresh

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/SitePageIndexerTests.swift`

- [ ] **Step 1: Add site page query**

In `SemanticsEditorSheet`, add:

```swift
@Environment(\.modelContext) private var context
@Query(filter: #Predicate<PublishedSitePage> { $0.siteHost == "hadassah.moscow" })
private var indexedPages: [PublishedSitePage]
```

If `@Environment(\.modelContext)` already exists in the file from a compile fix, keep one declaration.

- [ ] **Step 2: Replace refresh stub with real refresh**

Replace `refreshSitePages()` with:

```swift
private func refreshSitePages() {
    isRefreshingPages = true
    message = "Обновляю страницы сайта..."
    Task {
        do {
            let freshPages = try await SitePageIndexer().fetchPages()
            for page in indexedPages {
                context.delete(page)
            }
            for page in freshPages {
                context.insert(page)
            }
            try? context.save()
            message = "Индекс сайта обновлён: \(freshPages.count) страниц."
        } catch {
            message = "Не удалось обновить страницы сайта. Можно продолжить со старым индексом."
        }
        isRefreshingPages = false
    }
}
```

- [ ] **Step 3: Keep old index on failure**

Confirm the catch branch does not delete existing pages. Deletion must happen only after `fetchPages()` returns successfully, as shown in Step 2.

- [ ] **Step 4: Run indexer tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SitePageIndexerTests
```

Expected: tests pass.

- [ ] **Step 5: Manual check**

Open Semantics and click "Обновить страницы сайта". If the site is reachable, the message should show the number of indexed pages. If network fails, the message should say the old index is kept.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift
git commit -m "Wire manual site index refresh"
```

---

### Task 11: Update Test Containers And Model Registration

**Files:**
- Modify tests that create `ModelContainer(for: Topic.self, ...)`
- Likely files: `SEOContentCreator/SEOContentCreatorTests/*Tests.swift`

- [ ] **Step 1: Find affected containers**

Run:

```bash
rg -n "ModelContainer\\(" SEOContentCreator/SEOContentCreatorTests
```

Expected: list of tests with explicit SwiftData model registration.

- [ ] **Step 2: Update each container that includes `Topic.self`**

For each `ModelContainer(for: Topic.self, ...)`, add:

```swift
SemanticKeyword.self, PublishedSitePage.self
```

Example target shape:

```swift
let container = try ModelContainer(
    for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
         GenerationJob.self, StageTemplate.self, GeneratedImage.self,
         ExternalDocument.self, SemanticKeyword.self, PublishedSitePage.self,
    configurations: config
)
```

- [ ] **Step 3: Run full tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS'
```

Expected: tests pass or only unrelated pre-existing Keychain prompts appear. If Keychain prompts block the run, report that manual Xcode test verification is needed for those tests.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreatorTests
git commit -m "Register semantic models in tests"
```

---

### Task 12: Final Verification And Documentation Notes

**Files:**
- Modify: `ai/current-task.md`
- Modify: `ai/changelog.md` only if the project workflow asks for a completed implementation note later.

- [ ] **Step 1: Run focused unit tests**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/SemanticKeywordBackfillTests -only-testing:SEOContentCreatorTests/SemanticPromptRendererTests -only-testing:SEOContentCreatorTests/SemanticAgentResponseParserTests -only-testing:SEOContentCreatorTests/SemanticMockKeywordCollectorTests -only-testing:SEOContentCreatorTests/SemanticAgentAnalyzerTests -only-testing:SEOContentCreatorTests/SitePageHTMLParserTests -only-testing:SEOContentCreatorTests/SitePageIndexerTests -only-testing:SEOContentCreatorTests/SemanticKeywordMergerTests
```

Expected: all focused semantic tests pass.

- [ ] **Step 2: Run full test suite**

```bash
xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`. If Keychain tests trigger macOS prompts, record that as a manual verification limitation and run the focused semantic tests as the reliable automated gate.

- [ ] **Step 3: Manual app verification**

Check these flows:

- Existing topic with legacy `semantics` opens in Semantics and shows accepted rows.
- Accept selected, reject selected, and make required update the table.
- `{{семантика}}` includes accepted and required rows only.
- Semantic Agent sheet generates mock queries.
- OpenAI analysis either returns structured rows or shows a clear error.
- Saving agent rows stores them as pending.
- Refresh site pages succeeds or keeps the old index on failure.

- [ ] **Step 4: Check protected files and memory changes**

Run:

```bash
git diff --name-only
```

Expected: no protected architecture files changed except controlled memory files explicitly allowed by the active workflow.

- [ ] **Step 5: Update current task handoff**

Modify `ai/current-task.md`:

```markdown
Stage: review

## Relevant files

- `docs/superpowers/specs/2026-07-02-semantic-agent-design.md`
- `docs/superpowers/plans/2026-07-02-semantic-agent.md`
- `SEOContentCreator/SEOContentCreator/Models/SemanticKeyword.swift`
- `SEOContentCreator/SEOContentCreator/Models/PublishedSitePage.swift`
- `SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift`
- `SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift`

## Agent handoff

What changed: implemented first semantic agent workflow with mock query collection, OpenAI analysis, manual decisions, and hadassah.moscow page index.

Open risks: real Wordstat API remains future work; live site refresh depends on hadassah.moscow availability; OpenAI output is strictly parsed and may require retry.

Next agent should check: run task-finish only after user validates the manual app flow.
```

- [ ] **Step 6: Commit final task state**

```bash
git add ai/current-task.md
git commit -m "Update semantic agent task handoff"
```

---

## Self-Review

Spec coverage:

- Keyword decision table: Task 8.
- Preserve legacy semantics: Tasks 1 and 2.
- Mock query collection: Task 4 and Task 9.
- OpenAI analysis: Task 5 and Task 9.
- Store accepted, rejected, pending: Tasks 1, 7, and 8.
- User control: Tasks 8 and 9.
- Local `hadassah.moscow` index: Tasks 3, 6, and 10.
- Manual site refresh: Task 10.
- URL/title/meta description/H1/H2 fields: Task 3.
- Cannibalization details: Tasks 4, 5, 7, and 9.
- Prompt includes only accepted and required: Task 2.
- Tests and manual checks: Tasks 1-12.

Type consistency:

- `SemanticKeyword`, `PublishedSitePage`, `SemanticAgentKeywordResult`, and enum names are introduced before use.
- UI uses enum `label` properties defined on the model enums.
- Analyzer uses the existing `StageExecutor.StreamProvider` and `KeychainService` pattern.

Scope control:

- Real Wordstat API, manual import, full-page text extraction, automatic refresh, and advanced index history remain out of scope.
