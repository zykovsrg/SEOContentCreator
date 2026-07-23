# Reader Intent and Semantics Coordination — Design

Date: 2026-07-23

Status: approved in conversation; awaiting written-spec review

Updates the preparation order and semantic-input rules described in:

- `2026-07-22-reader-intent-personal-prompt-defaults-design.md`
- `2026-07-22-semantic-autocollection-design.md`

## Context

The topic workspace currently shows `Семантика` before `Задача читателя`.
Their entry points also behave differently: reader intent opens a dedicated
sheet, while Semantics only switches the right inspector to its semantics tab.
When the inspector is already selected, hidden, or outside the user's current
focus, clicking the Semantics row can appear to do nothing.

The desired editorial order is:

1. formulate the reader's practical task;
2. collect and clean real search queries;
3. evaluate those queries against the topic, article goal, and target audience;
4. use the resulting semantics in later article stages.

The reader-intent framework supplied by the user defines:

- visible query and hidden practical goal;
- reader profile and situation;
- measurable success criterion;
- constraints, fears, and other barriers;
- solution type and concrete output format.

The semantic methodology supplied by the user requires:

- real Yandex Wordstat demand rather than invented demand;
- question masks, related queries, abbreviations, colloquial variants, and
  Cyrillic/Latin spellings;
- removal of student, academic, duplicated, and off-topic queries;
- AI relevance analysis against the future article's topic and target audience;
- ten additional relevant long-tail queries of 3–7 words;
- close treatment of the most relevant accepted queries in headings and related
  vocabulary without keyword stuffing.

The existing semantic auto-collection pipeline already implements Wordstat seed
planning, masks, stop words, normalization, frequency filtering, AI relevance
analysis, long-tail expansion, cannibalization checking, and an auditable funnel.
This change coordinates that pipeline with the saved reader-intent card.

## Goals

- Make the preparation order visually explicit: `Задача читателя` first,
  `Семантика` second.
- Keep the workflow flexible: missing reader intent warns but never blocks
  opening or running Semantics.
- Make a click on the Semantics preparation row produce an unmistakable result.
- Pass saved reader-intent context to semantic seed planning and relevance
  analysis.
- Prevent the first coordinated semantic collection from immediately making the
  reader-intent card look stale.
- Preserve stale detection for later manual changes to accepted or required
  semantic queries.
- Cover the changed behavior with focused automated tests and a manual UI check.

## Non-goals

- Making reader intent or semantics a new `PipelineStage`.
- Blocking Semantics until reader intent is complete.
- Replacing Wordstat demand with AI-generated query volume.
- Adding an external clustering service.
- Changing Wordstat region, device, threshold, top-100, funnel, or
  cannibalization defaults.
- Removing the existing Semantics inspector tab.
- Changing the stored `ReaderIntent` or `SemanticKeyword` schema.
- Automatically rewriting reader-intent fields after semantics change.

## User Workflow

1. In `Подготовка статьи`, the user first sees `Задача читателя`.
2. The user fills it manually or generates and edits an AI draft, then saves.
3. The user opens `Семантика` from the second row.
4. A dedicated Semantics sheet opens. The existing inspector tab remains
   available as a compact secondary entry point.
5. If reader intent is missing, the sheet shows a non-blocking warning that
   collection can continue but audience and practical-goal relevance will be
   less precise.
6. Automatic collection uses the saved card when planning Wordstat seeds and
   judging query relevance.
7. After a successful automatic run, the application records the resulting
   accepted/required query set as the reader-intent card's current semantic
   snapshot.
8. If the user later changes accepted or required queries manually, the existing
   `Семантика изменилась` state appears and invites a reader-intent review.

The preparation rows are recommendations, not gates. Both editors remain
available in any order.

## Workspace UI

### Preparation rail

Render rows in this order:

1. `Задача читателя`
2. `Семантика`

Keep the existing status text and icons. Do not add a new completion percentage
or merge these rows into the normal article-stage count.

### Semantics entry point

The Semantics preparation row opens a dedicated sheet instead of only changing
the right inspector selection.

The sheet:

- reuses the existing semantics editor rather than duplicating its behavior;
- provides a visible title and Close action appropriate for a modal sheet;
- supports the existing collection, filtering, decision, funnel, and reference
  actions;
- shows a compact warning when no reader-intent card is saved;
- does not disable editing or collection because of that warning.

The existing inspector Semantics tab remains unchanged for users who prefer
editing beside the article.

### Missing-intent message

Use concise meaning equivalent to:

`Задача читателя не заполнена. Семантику можно собрать, но оценка интересов и практической цели аудитории будет менее точной.`

The first implementation shows text only. It does not open a second sheet from
inside the Semantics sheet. The preparation rail remains the entry point for
opening `Задача читателя`.

## Semantic AI Inputs

### Seed planning

Extend `SemanticSeedPlanner.userPrompt` with the compact output from
`ReaderIntentPromptRenderer`.

The planner must use the card to choose relevant:

- synonyms and professional/colloquial variants;
- abbreviations;
- Russian and English spellings;
- question masks;
- qualifier tails.

It must still select masks only from the configured reference list and must not
invent measured demand.

If the card is missing, render the existing explicit fallback
`Карта задачи читателя не заполнена.` The planner continues using topic title and
article type.

### Relevance analysis

Extend `SemanticAgentAnalyzer.userPrompt` with the same compact reader-intent
block.

The analyzer must:

- retain only queries relevant to the topic and the reader's practical task;
- reject student, academic, duplicated, and wrong-intent formulations;
- distinguish the visible query from the hidden practical goal;
- prefer queries useful to the target audience described in the card;
- generate ten plausible long-tail queries of 3–7 words aligned with that
  audience and goal.

The current rule filter remains the first defense for configured stop words.
The AI analysis is a semantic second defense, not a replacement for deterministic
rules.

### Prompt safety

The reader-intent block is context, not an instruction to:

- fabricate Wordstat frequency;
- force every accepted query into the article;
- make unsupported medical or commercial promises;
- exploit fears described in the card.

## Semantic Snapshot Synchronization

The existing reader-intent design captures accepted/required semantics when the
card is saved and marks it stale when that set changes. With the new visual order,
a card may legitimately be saved before any semantics exist. The first automatic
collection would otherwise make it stale immediately even though that collection
was guided by the card.

After `SemanticCollectionRunner` successfully merges surviving queries:

1. compute `ReaderIntent.acceptedSemanticSnapshot(for: topic)`;
2. if the topic has a saved reader-intent card, assign that normalized set to
   `readerIntent.semanticSnapshot`;
3. update `readerIntent.updatedAt`;
4. save it in the same successful run transaction.

Do not synchronize the snapshot:

- before a semantic run succeeds;
- when Wordstat returns nothing;
- when deterministic rules drop everything;
- after a failed AI or cannibalization step;
- after later manual accepted/required decision changes.

This makes automatic collection a coordinated continuation of the saved intent
while preserving the stale warning for subsequent human edits.

## Error Handling

- Opening the Semantics sheet never requires an API key or Wordstat token.
- Missing credentials continue to use the existing readable collection errors.
- Missing reader intent is a warning, not an error.
- A failed collection leaves both topic semantics and the saved semantic snapshot
  unchanged.
- Closing the sheet does not discard semantic decisions because the existing
  semantics editor edits the topic directly.

## Testing

Add focused automated tests for:

1. preparation-row order as a small pure descriptor or other testable view model,
   avoiding brittle screenshot assertions;
2. semantic seed-planner prompt includes every relevant saved reader-intent
   field and the explicit missing-card fallback;
3. semantic relevance prompt includes the reader-intent block and keeps the
   academic/wrong-intent/long-tail rules;
4. successful automatic collection refreshes the reader-intent semantic snapshot;
5. a failed collection does not refresh the snapshot;
6. later manual changes to accepted/required queries still produce
   `ReaderIntentStatus.stale`;
7. the Semantics preparation action drives dedicated-sheet presentation state.

Use the current Swift Testing and in-memory SwiftData patterns. Do not add a new
test framework.

Manual UI verification:

1. open a topic and confirm `Задача читателя` is above `Семантика`;
2. click Semantics with the inspector hidden and visible;
3. confirm the dedicated sheet opens every time;
4. confirm the missing-intent warning is readable and non-blocking;
5. save reader intent, run collection, and confirm both preparation rows are
   ready rather than immediately stale;
6. manually change an accepted/required query and confirm the stale warning
   returns;
7. check the changed states in the application's supported light and dark
   appearances.

## Compatibility and Risk

No database migration is required. The change uses existing fields and services.

The main behavioral risk is hiding a real mismatch between intent and semantics
by refreshing the snapshot after automatic collection. This is limited to the
successful coordinated run that already used the card as an input. Any later
manual change remains visible through stale detection.

The existing Semantics inspector stays available, preserving the established
side-by-side workflow. The dedicated sheet only changes the preparation-row
entry point that currently appears unresponsive.

## Done Criteria

- The preparation rows appear as `Задача читателя → Семантика`.
- Clicking the Semantics preparation row always opens a visible dedicated sheet.
- Missing reader intent warns but does not block semantics work.
- Both semantic AI prompt stages receive the saved reader-intent card.
- Successful coordinated collection updates the semantic snapshot only after all
  collection layers succeed.
- Later manual semantic changes still mark reader intent stale.
- Focused automated tests pass and the manual UI checklist is completed or its
  remaining items are reported explicitly.
