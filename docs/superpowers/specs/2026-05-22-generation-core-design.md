# Technical Design: Sub-project 3 — Generation Core

Date: 2026-05-22
Status: approved by user (brainstorming session)
Related product spec: `docs/superpowers/specs/2026-05-19-content-system-redesign-design.md` (v7.4)
Related frontend design: `docs/superpowers/specs/2026-05-21-frontend-design.md`

This document captures **technical architecture decisions** for sub-project 3.
Product semantics, entity definitions, and UI behaviour are in the main spec. This doc adds:
technology stack, service-layer design, data model field lists, scope boundaries.

---

## Technical Decisions

| Decision | Choice | Reason |
|---|---|---|
| AI provider | OpenAI (GPT-4.1 default / GPT-4o selectable) | User preference |
| API key storage | macOS Keychain (`Security.framework`) | Standard for macOS apps; key never written to files |
| Response delivery | Streaming (`AsyncThrowingStream<String, Error>`) | Articles are 2 000–5 000 words; streaming UX essential |
| Default model | `gpt-4.1` | Better instruction-following, lower cost per token than gpt-4o |
| Architecture pattern | Layered services — Variant B | Clean boundaries, TDD-friendly, consistent with existing app |
| Concurrency | Swift structured concurrency (`async/await`, `Task`) | Native to SwiftUI, safe for single-user app |

---

## New Data Models (SwiftData)

### ArticleVersion
Одна запись в ленте версий (спека §2.3).

```
id: UUID
stageLabel: String          // "draft" | "productBlocks" | "semanticsInText" |
                             // "style" | "seoCheck" | "factcheck" | "finalReview" |
                             // "manualEdit" | "rollback" | "importFromDocs"
sourceType: enum            // generated | manualEdit | acceptedFull | acceptedPartial |
                             // rollback | importFromDocs
text: String
h1: String?                 // populated from semanticsInText stage
seoTitle: String?
seoDescription: String?
agentName: String?          // if sourceType == generated
templateID: UUID?           // StageTemplate used, if generated
modelName: String?          // OpenAI model name, if generated
note: String?
isArchived: Bool = false
createdAt: Date
topic: Topic                // @Relationship(.cascade, inverse: \Topic.versions)
```

Topic additions:
```
versions: [ArticleVersion]  // @Relationship
currentVersionID: UUID?     // pointer to head version (nil = no text yet)
```

---

### GenerationJob
Запись каждого запуска ИИ (спека §2.10).

```
id: UUID
stageLabel: String
agentName: String
modelName: String
status: enum                // running | success | error | cancelled
startedAt: Date
finishedAt: Date?
errorMessage: String?
resultVersionID: UUID?      // set to ArticleVersion.id on success
topic: Topic                // @Relationship(.cascade, inverse: \Topic.jobs)
```

---

### StageTemplate
Шаблон промта для этапа × тип статьи (спека §2.5).

```
id: UUID
stageName: String           // "draft" | "productBlocks" | "semanticsInText"
articleTypeName: String?    // nil = universal (applies to all types)
systemPrompt: String
userPromptTemplate: String  // contains {{variable}} placeholders
modelName: String = "gpt-4.1"
temperature: Double = 0.6
maxTokens: Int = 8000
templateVersion: Int = 1
createdAt: Date
updatedAt: Date
```

Seed data is inserted on first launch (one template per stage, universal article type).
Templates are stored in SwiftData and editable in a future sub-project (Шаблоны section §4.4).

---

## Service Layer (Variant B)

### KeychainService
```swift
static func save(apiKey: String) throws
static func loadAPIKey() throws -> String   // throws KeychainError.notFound if absent
static func deleteAPIKey() throws
```
Uses `Security.framework` `SecItemAdd` / `SecItemCopyMatching`.

---

### PromptBuilder
```swift
func build(
    template: StageTemplate,
    topic: Topic,
    currentText: String?
) -> (system: String, user: String)
```

Supported variables and their sources:

| Variable | Source |
|---|---|
| `{{тема}}` | `topic.title` |
| `{{тип}}` | `topic.articleType.name` |
| `{{объём}}` | `topic.targetLength` |
| `{{направление}}` | direction KnowledgeNode content |
| `{{врач_данные}}` | doctor KnowledgeNode content (if attached) |
| `{{преимущества}}` | attached KnowledgeNodes of type `.advantage` |
| `{{источники_направления}}` | priority source URLs from direction node |
| `{{семантика}}` | formatted list of semantics queries (text + frequency + status) |
| `{{текущий_текст}}` | `currentText` parameter |
| `{{замечания}}` | reserved — used in checking stages (sub-project 4) |

Unknown `{{…}}` placeholders are left as-is (not an error).

---

### OpenAIClient
```swift
func streamCompletion(
    system: String,
    user: String,
    model: String
) -> AsyncThrowingStream<String, Error>
```
- Uses `URLSession.bytes` (streaming SSE over HTTP/2).
- Endpoint: `POST https://api.openai.com/v1/chat/completions` with `stream: true`.
- Parses `data: {...}` server-sent events, yields `delta.content` fragments.
- Throws `OpenAIError.unauthorized` on 401, `OpenAIError.rateLimited` on 429, etc.

---

### StageExecutor
```swift
func execute(
    stage: PipelineStage,
    topic: Topic,
    productBlockTypes: [String] = [],   // for productBlocks stage only
    in context: ModelContext
) async throws
```

Execution flow:
1. Check `KeychainService.loadAPIKey()` → throw `KeychainError.notFound` if missing (UI shows settings prompt).
2. Resolve `StageTemplate` for `(stage, topic.articleType)` from SwiftData.
3. Create `GenerationJob(status: .running)`, insert into context.
4. Call `PromptBuilder.build(template:topic:currentText:)`.
5. Stream from `OpenAIClient.streamCompletion(...)` → publish tokens to UI via `@Published var streamingText`.
6. On stream completion: create `ArticleVersion`, set `topic.currentVersionID`, update job `status = .success`.
7. On error: update job `status = .error`, `errorMessage = error.localizedDescription`. No version created.

---

## AI Stages in Sub-project 3

### Черновик (Draft) — спека §5 шаг 2
- Agent name: `"ИИ-автор"`
- Variables: `{{тема}}`, `{{тип}}`, `{{объём}}`, `{{направление}}`, `{{врач_данные}}`, `{{преимущества}}`, `{{источники_направления}}`
- Precondition: `topic.title ≠ nil && topic.articleType ≠ nil && topic.direction ≠ nil`
- Output: `ArticleVersion(stageLabel: "draft")`

### Продуктовые блоки (Product Blocks) — спека §5 шаг 3
- Agent name: `"ИИ-автор"`
- Pre-run UI: sheet with checkboxes for available product block types (sourced from KnowledgeNodes)
- Variables: `{{текущий_текст}}`, `{{преимущества}}`, `{{врач_данные}}` + selected block names injected into prompt
- Precondition: `topic.currentVersionID ≠ nil` (needs a draft first)
- Output: `ArticleVersion(stageLabel: "productBlocks")`

### Семантика-в-текст (Semantics in Text) — спека §5 шаг 4
- Agent name: `"ИИ-автор"`
- Variables: `{{текущий_текст}}`, `{{семантика}}`
- Precondition: `topic.currentVersionID ≠ nil && topic.semantics ≠ empty`
- Output: `ArticleVersion(stageLabel: "semanticsInText")` with `h1`, `seoTitle`, `seoDescription`
  - Model returns these fields in a structured JSON block at the end of its response (parsing strategy defined in implementation plan)
- Agent also returns a list of embedded queries + uncertainty notes in the same JSON block; stored in `GenerationJob` and shown in job log

---

## UI Components

### VersionLaneView (right sidebar, TopicWorkspaceView)
- `@Query` `ArticleVersion` filtered by `topic`, sorted by `createdAt DESC`
- Toggle: «По времени» (flat list) / «По этапам» (grouped by `stageLabel`)
- Row: stage icon, timestamp, source badge, agent name
- Tap → sets `comparisonVersionID` in workspace (shows that version in left column)
- «Сделать текущей» button → creates `ArticleVersion(stageLabel: "rollback", sourceType: .rollback)`, updates `currentVersionID`

### SideBySideView (centre of TopicWorkspaceView)
- **Left column**: current version text, read-only `ScrollView`
- **Right column**:
  - While streaming: `Text` of `streamingText` partial string, auto-scroll
  - After completion: paragraph-level diff view (paragraph-aligned, highlight changed/added/removed)
- When no active generation and no comparison selected: right column = `TextEditor` for manual edit

**Diff algorithm**: split both texts by `\n\n`, apply LCS on paragraph list, render:
- unchanged paragraph: plain
- changed: yellow background
- added: green background
- removed: red strikethrough (shown in left column counterpart)

### AcceptRejectBar (below SideBySideView)
- «Принять всё» → `StageExecutor`-independent: copies new version text to new `ArticleVersion(sourceType: .acceptedFull)`
- «Принять частично» → sheet with paragraph checkboxes; assembles hybrid text → `ArticleVersion(sourceType: .acceptedPartial)`
- «Отклонить» → discards `streamingText`/new version, no write to SwiftData

### JobLogView (bottom drawer, TopicWorkspaceView)
- `@Query` `GenerationJob` for topic, sorted by `startedAt DESC`
- Row: stage label, timestamp, status icon (⏳/✓/⚠), model name
- Expandable row: `errorMessage` if `status == .error`

### SettingsView (`⌘,` App Preferences)
- `SecureField` for OpenAI API key → on submit: `KeychainService.save(apiKey:)`; on clear: `KeychainService.deleteAPIKey()`
- Model picker: `["gpt-4.1", "gpt-4o", "gpt-4o-mini"]` — saved to `UserDefaults`
- «Проверить соединение» button → sends minimal request, shows ✓ or error message

---

## Scope Boundaries

### Входит в под-проект 3

- `ArticleVersion`, `GenerationJob`, `StageTemplate` SwiftData models
- `Topic` migration: add `versions` relationship + `currentVersionID`
- `KeychainService`, `PromptBuilder`, `OpenAIClient`, `StageExecutor`
- Stages: `draft`, `productBlocks`, `semanticsInText`
- `SideBySideView` with streaming + paragraph diff
- `VersionLaneView` (by-time and by-stages modes)
- `AcceptRejectBar` (full + partial + reject)
- `JobLogView`
- `SettingsView` (API key + model)
- Starter `StageTemplate` seed data (one per stage, universal)
- Unit tests for all service-layer classes

### Не входит (отложено)

| Feature | Sub-project |
|---|---|
| `StageTemplateEditorView` (Шаблоны раздел §4.4) | 5 или 6 |
| Проверяющие этапы (SEO, фактчекинг, вычитка) | 4 |
| Панель замечаний (карточки ✓/✗) | 4 |
| Очередь и автоматизация | 5 |
| Стоимость в токенах / рублях | 6 / расширенный режим |
| «Быстрая проверка» (без темы) | 6 |
| Импорт семантики из Топвизора | 4 или 5 |
| Мягкие подсказки (алгоритмические) | вместе с ручной правкой |

---

## Testing Strategy

- `KeychainService` — unit tests (save/load/delete, not-found error)
- `PromptBuilder` — unit tests (all variables substituted correctly; unknown variables left as-is)
- `OpenAIClient` — unit tests with mock `URLSession` (stream parsing, error handling)
- `StageExecutor` — unit tests with mock `OpenAIClient` (success path, error path, missing key)
- `SideBySideView` / `VersionLaneView` — manual smoke tests (no `XCUITest`)
