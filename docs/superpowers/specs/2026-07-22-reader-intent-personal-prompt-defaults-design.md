# Reader Intent and Personal Prompt Defaults — Design

Date: 2026-07-22

Status: approved in conversation; awaiting written-spec review

## Context

The application already stores topic semantics, generates an editable article structure, and uses editable stage prompts assembled with shared AI roles and context blocks. The current structure prompt derives a two-line `Полезное действие`, but that result is embedded in `structureText`, is not stored as structured topic data, and cannot be reviewed independently by the SEO checker.

The user provided a reader-intent framework containing the visible query, hidden practical goal, reader context, success criterion, barriers, solution type and format, plus an eight-item semantic-coverage checklist. The useful parts should guide relevant stages without copying the full methodology or its B2B/B2C examples into every prompt.

Prompt defaults also need a new lifecycle. Today `StagePromptEditorView` saves the live stage prompt, role, shared blocks, and model parameters, while `Сбросить к стандартному` loads compile-time defaults and immediately saves them. Template migrations can overwrite previously edited prompts. The desired behavior is for every explicit Save to make the full saved editor state the user's protected personal default, with a separate explicit action for loading the current factory defaults shipped by the application.

## Goals

- Store one structured reader-intent card per topic.
- Let the user create the card manually or generate an editable draft with OpenAI.
- Use accepted and required semantic queries as evidence for intent, not as mandatory headings or phrases.
- Pass a compact intent representation only to the stages that need it.
- Update the current modified stage prompts without replacing their existing text wholesale.
- Make every explicit prompt-editor Save create a full personal-default snapshot.
- Protect personal defaults and live prompts from future factory-default migrations.
- Preserve the existing non-linear pipeline: a missing reader-intent card warns but does not block a stage.

## Non-goals

- Real keyword collection from Wordstat, DataForSEO, or another external search-demand provider.
- Treating AI-generated keyword ideas as measured search demand.
- Adding reader intent as a new `PipelineStage`.
- Keeping a history of multiple reader-intent revisions.
- Automatically regenerating or saving intent after semantics change.
- Passing the reader-intent card to product-block insertion, fact checking, or final copy review.

## User Workflow

1. The user collects, imports, or manually enters semantic queries and explicitly accepts or requires the useful queries.
2. In the topic workspace, the user opens `Задача читателя` from a preparation section shown before the article stages.
3. The user either fills the card manually or presses `Сформировать с ИИ`.
4. OpenAI returns a structured draft. The draft remains local to the editor until the user presses `Сохранить`.
5. The user reviews assumptions, edits any field, selects the required coverage categories, and saves.
6. The structure, draft, semantics-in-text, and SEO-check stages receive a compact rendered form of the saved card.
7. If accepted/required semantics later change, the card shows a stale warning. The user may open it and explicitly run `Обновить с ИИ`; nothing changes automatically.

## Data Model

### ReaderIntent

Add a dedicated SwiftData model with an optional one-to-one relationship from `Topic` and a cascade delete rule.

Persisted fields:

- `uuid: UUID`
- `query: String`
- `audienceContext: String`
- `hiddenGoal: String`
- `successCriterion: String`
- `barriers: String`
- `solutionTypeRaw: String`
- `solutionFormat: String`
- `coverageRaw: [String]`
- `sourceRaw: String`
- `semanticSnapshot: [String]`
- `createdAt: Date`
- `updatedAt: Date`
- `topic: Topic?`

`Topic.readerIntent` is optional so existing topics remain valid after a lightweight schema update.

Use typed application enums around persisted raw values:

- `ReaderIntentSolutionType`: `explanation`, `algorithm`, `comparison`, `directOffer`, `mixed`.
- `ReaderIntentCoverage`: `definition`, `currentRelevance`, `choiceComparison`, `evidence`, `socialProof`, `applicationContext`, `risksLimitations`, `practicalSolution`.
- `ReaderIntentSource`: `manual`, `ai`.

The human-readable task formula is derived from fields and is not persisted separately.

### ReaderIntentDraft

Use a non-persisted value type for editor state and AI results. Opening the editor copies the saved model into a draft. Cancel and window close discard the draft. Save validates and applies the draft to `ReaderIntent` in one operation.

Only `query` and `hiddenGoal` are required to save. All other fields may remain empty and can be completed manually later.

### Semantic staleness

Store a normalized, sorted snapshot of the accepted and required query strings at the time the intent is saved. Compare that snapshot with the current normalized list to derive `isStale`. Do not use an unstable process hash and do not auto-update the model.

## AI Generation

Add bounded components with separate responsibilities:

- `ReaderIntentAnalyzer`: obtains the API key, calls the existing streaming client, and returns raw collected text.
- `ReaderIntentPromptBuilder`: builds a stable system instruction plus dynamic topic context.
- `ReaderIntentResponseParser`: validates the strict JSON response and produces `ReaderIntentDraft`.
- `ReaderIntentPromptRenderer`: creates the compact block used by stage prompts.

The analyzer receives only:

- topic title and article type;
- primary direction;
- accepted and required semantic queries;
- every knowledge-base node attached to this topic (deduplicated title and content), plus the selected doctor, advantages, and direction sources; data from other topics is not included.

It must identify unsupported audience or fear assumptions as hypotheses, avoid fear-based marketing, never invent medical facts, and select only relevant coverage categories rather than all eight by default.

Expected response shape:

```json
{
  "query": "...",
  "audienceContext": "...",
  "hiddenGoal": "...",
  "successCriterion": "...",
  "barriers": "...",
  "solutionType": "explanation|algorithm|comparison|directOffer|mixed",
  "solutionFormat": "...",
  "coverage": ["definition", "risksLimitations", "practicalSolution"]
}
```

The parser rejects invalid JSON and unknown enum values. A failed call never changes the saved `ReaderIntent`. A missing API key or empty/invalid response is shown as a readable error while manual editing remains available.

AI generation is allowed without accepted semantics, but the UI shows a lower-confidence warning and the prompt explicitly tells the model that semantic evidence is absent.

## Compact Prompt Rendering

Register a new template variable:

```text
{{задача_читателя}}
```

Render the saved card as a concise Russian block:

```text
Задача читателя:
- Запрос: ...
- Кто и в какой ситуации: ...
- Практическая задача: ...
- Ответ полезен, если: ...
- Барьеры и сомнения: ...
- Тип и формат решения: ...
- Необходимое покрытие: ...
```

Omit empty optional lines. If no card exists, render `Карта задачи читателя не заполнена.` without inferring or inventing content.

## Stage Prompt Integration

Modify the current repository versions of the default prompts; do not restore older prompt wording.

### Structure

- Add `{{задача_читателя}}`.
- Add `{{семантика}}` with an explicit instruction that queries are evidence of reader questions and context, not a list of mandatory headings or exact phrases.
- Use selected coverage categories as a completeness guide, not a fixed outline.
- Remove the instruction to print `Полезное действие` inside `structureText`.
- Return only the editable H1/H2/H3 plan.

### Draft

- Add `{{задача_читателя}}` directly alongside `{{структура}}`.
- Treat the card as the text's frame but never print the card itself.
- Preserve the current modified editorial requirements and avoid duplicating the full intent methodology.

### Semantics in text

- Add `{{задача_читателя}}`.
- Align H1, Title, and Description with the practical task while avoiding unsupported promises.

### SEO check

- Add `{{задача_читателя}}`.
- Check whether the page answers the practical intent and covers the categories selected in the card.
- Do not demand every coverage category.
- Add `Интент` and `Полнота` to the allowed remark categories.

### Unchanged stages

Do not add the card to product blocks, fact checking, final review, images, or prompt analysis.

## Workspace UI

Add a `Подготовка статьи` section before the normal stage list in the topic workspace. It contains entry points for the existing semantics editor and the new `Задача читателя` editor. This section does not add cases to `PipelineStage`.

The intent row displays one of three states:

- missing: `Не заполнена`;
- ready: `Готова` plus a one-line hidden-goal summary;
- stale: `Семантика изменилась — рекомендуется обновить`.

`ReaderIntentSheet` contains:

- topic title and generation/update action;
- editable fields for every persisted card component;
- a solution-type picker;
- free-form solution-format input;
- eight coverage toggles;
- a derived formula preview;
- Cancel and Save actions;
- inline progress and readable errors.

The OpenAI action is always explicit and never starts on open or save.

Add a compact intent banner above the structure editor with the current hidden-goal summary and `Редактировать`. A missing card shows a warning and an edit action but does not disable structure generation.

## Personal Prompt Defaults

### Snapshot fields

Add optional personal-default fields and an explicit `hasPersonalDefault` flag to distinguish an absent snapshot from valid `nil` values such as default reasoning effort.

`StageTemplate` snapshot includes:

- user prompt template;
- model name;
- temperature;
- max tokens;
- reasoning effort;
- snapshot timestamp.

`AIRole` snapshot includes:

- mandate;
- enabled block keys;
- snapshot timestamp.

`ContextBlock` snapshot includes:

- text;
- snapshot timestamp.

Role and context-block snapshots remain shared, matching the current live data model. Saving them from one stage affects every other stage that uses the same role or block.

### Save behavior

Move save/snapshot logic out of the SwiftUI view into `PromptPersonalDefaultsService` so it can be tested independently.

One explicit `Сохранить` operation:

1. applies the editor state to the live `StageTemplate`, selected `AIRole`, and displayed shared `ContextBlock` objects;
2. increments the live object versions using the current versioning rules;
3. copies the resulting full state into the corresponding personal-default snapshot fields;
4. updates timestamps;
5. reports `Сохранено как мой дефолт · версия N`.

### Restore behavior

Rename the current reset action to `Сбросить к моему дефолту`. It loads the personal snapshots into unsaved editor state and does not persist automatically. The user reviews the loaded values and presses Save to apply them.

Add `Вернуть стандарт приложения`. It loads the current values from `StageTemplateDefaults`, `RoleDefaults`, and `ContextBlockDefaults` into unsaved editor state. Before loading shared role or block values, show a warning that saving will affect other linked stages. Loading or cancelling does not mutate persisted state. Pressing Save applies the factory values and makes them the new personal defaults.

## Migration Strategy

Introduce an idempotent `StagePromptIntentMigration` and advance the template-defaults migration version from 8 to 9.

For each targeted stored stage prompt:

1. If the new stage marker and `{{задача_читателя}}` already exist, do nothing.
2. Otherwise insert the stage-specific intent addition at a known stable anchor in the current stored text.
3. If the anchor is absent because the prompt was customized, append a clearly delimited stage-specific addition.
4. Never replace the complete stored text with `StageTemplateDefaults`.
5. Ensure repeated runs do not duplicate markers, placeholders, categories, or semantic instructions.

After the v9 prompt upgrade, capture every live `StageTemplate`, `AIRole`, and `ContextBlock` without an existing snapshot as its first personal default. Fresh installs seed the new factory prompts and then capture them as their initial personal defaults.

After v9, normal factory-default updates must not overwrite live values or personal snapshots. They become available through `Вернуть стандарт приложения`. Any future exceptional content migration that needs to modify a personal prompt requires an explicit, separately designed migration rather than joining the old cascade overwrite list.

## Error Handling

- Missing API key: show the existing readable key error and keep manual editing enabled.
- OpenAI or network failure: keep both persisted intent and local draft unchanged.
- Invalid JSON or enums: show a parse error and do not save AI output.
- Empty semantics: show a low-confidence warning; allow manual and AI workflows.
- Changed semantics: show stale status only; never regenerate automatically.
- Empty optional fields: omit them from prompt rendering.
- Missing migration anchor: append an idempotent marked block instead of overwriting text.
- Factory restore with shared role/block data: require confirmation before loading the factory values into the editor.

## Testing Strategy

### Unit tests

- Persist a `ReaderIntent` and load a `Topic` without one.
- Validate enum raw-value fallbacks and derived task formula.
- Parse valid AI JSON; reject invalid JSON and unknown enum values.
- Verify analyzer prompts include topic context and only accepted/required semantics.
- Detect staleness from normalized semantic snapshots.
- Render a compact card, omit empty fields, and render the empty fallback.
- Substitute `{{задача_читателя}}` in `PromptBuilder`.
- Verify the card appears only in structure, draft, semantics-in-text, and SEO-check defaults.
- Verify structure receives semantics plus the non-mechanical-use instruction.
- Verify SEO categories include intent and completeness.
- Upgrade customized prompt text without replacing it.
- Verify migration idempotence and fallback append behavior.
- Capture initial personal defaults after migration.
- Save full stage, role, block, and model state as a personal default.
- Load personal defaults without persistence until Save.
- Load factory values without persistence until Save.
- Verify shared role/block snapshots remain consistent across linked stages.

### Build and manual checks

- Build the application and test target.
- Run the relevant unit-test suites, expanding to the full unit-test target when practical.
- Manually verify semantics -> intent generation -> edit -> save -> structure -> draft -> SEO check.
- Manually change accepted semantics and verify stale status.
- Manually verify intent generation failure leaves saved data unchanged.
- Manually save a modified full stage state, alter the editor, restore the personal default, and save again.
- Manually load the factory standard, confirm the shared-data warning, and verify no persistence occurs before Save.
- Open an existing database with v8 prompts and verify v9 preserves modified text while adding the intent blocks exactly once.

## Acceptance Criteria

- Every approved current-task Done criterion is covered by the implementation and tests.
- Existing topics and modified prompts survive migration without unrelated data loss.
- Reader intent is visible, editable, manually controllable, and used only by relevant stages.
- Semantics guide structure without becoming mandatory headings or phrases.
- Every explicit prompt-editor Save establishes the complete protected personal default.
- Factory defaults remain separately available only through an explicit restore action.
