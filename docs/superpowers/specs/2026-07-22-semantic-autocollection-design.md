# Semantic Auto-Collection Design

Date: 2026-07-22

Status: draft for user review

Supersedes the mock-collection part of `2026-07-02-semantic-agent-design.md`.

## Goal

Turn the Semantics stage into a one-click automatic pipeline: an AI agent plans
which seed phrases to pull, the app pulls real queries with frequencies from the
Yandex Wordstat API, and a three-layer funnel cleans the list. The user does not
approve anything mid-flight. Instead, every dropped query stays visible in a
funnel report with the layer and reason that removed it, so the user can audit
the run and override any decision afterwards.

This replaces `SemanticMockKeywordCollector`, which fabricates candidates like
"тема + лечение" and feeds them to a capable analyzer that has nothing real to
judge.

The pipeline follows the editorial methodology for building a semantic core:
seed masks with question words, minus-words for academic and student queries,
frequency-based filtering, relevance judgement, and long-tail expansion.

## Confirmed Scope

In scope:

- AI planner that produces topic synonyms, question masks, and qualifier tails.
- Real Yandex Wordstat API integration with frequencies.
- Rule layer: normalization, deduplication, minus-words, frequency threshold,
  top-100 cut.
- AI relevance layer, including rejection of academic phrasing and generation of
  long-tail queries of 3-7 words.
- Separate AI cannibalization layer against `PublishedSitePage`.
- Funnel journal storing every query with the layer and reason that dropped it.
- Funnel screen showing counts in and out per layer.
- Editable reference lists for minus-words and question masks in Templates.
- Removal of `SemanticMockKeywordCollector`.

Out of scope:

- Clustering and SERP comparison between Yandex XML and Google Mobile.
- Topvisor or other third-party rank-tracker imports.
- Manual paste/import of Wordstat exports.
- Automatic scheduled re-collection.
- Changing how `{{семантика}}` renders into prompts.

## Product Flow

1. The user opens a topic and clicks Semantics, then Collect.
2. The app runs the whole pipeline without further prompts.
3. When the run finishes, the funnel screen opens with per-layer results.
4. Surviving queries are saved to the topic as `accepted` semantic keywords.
5. The user reviews the funnel and flips any decision in the existing semantics
   table.

### Deliberate change from the 2026-07-02 design

The earlier design saved agent output as `pending` and required the user to
accept each row. This design saves survivors as `accepted` directly, because the
user asked for a fully automatic stage.

User control is preserved, but moves after the fact: nothing is hidden, every
drop is explained in the funnel, and every decision remains editable. The project
invariant that the AI must not act silently is satisfied by the funnel report,
not by an approval gate.

## Pipeline

```
Topic
 -> (1) SemanticSeedPlanner (LLM)   -> synonyms + masks + tails
 -> (2) WordstatClient              -> raw pool with frequencies
 -> (3) SemanticRuleFilter          -> minus-words, dedup, threshold, top 100
 -> (4) SemanticAgentAnalyzer (LLM) -> relevance, intent, long-tail expansion
 -> (5) SemanticCannibalizationChecker (LLM) -> vs published pages
 -> (6) Topic semantics
```

### Layer 1 — Seed planning

Input: topic title, article type, and relevant knowledge-base context.

Output: strict JSON with three lists.

- `synonyms` — naming variants of the topic: abbreviations, colloquial and
  professional terms, Latin and Cyrillic spellings. For "рак молочной железы"
  this covers "РМЖ", "рак груди", "карцинома молочной железы", "breast cancer".
- `masks` — the topic combined with question words drawn from the mask reference
  list. The agent selects which masks fit the topic; it does not invent the word
  list.
- `tails` — qualifier suffixes such as цена, лечение, симптомы, отзывы, and
  geography, chosen for this topic rather than hardcoded per article type.

Malformed JSON is a hard error with a retry-friendly message. The app never
guesses at a partial plan.

### Layer 2 — Wordstat pull

The client pulls including-phrases with frequencies for every seed phrase.

Defaults, confirmed with the user:

- Region: Moscow and Moscow region.
- Devices: all — desktop, mobile, tablet.

The client is defined behind a provider function, matching the existing
`OpenAIClient` and `StageExecutor.StreamProvider` pattern, so tests inject
fixtures instead of hitting the network.

Partial failure is tolerated: if some seeds fail, the run continues with what
returned and the funnel reports the failed seeds. A total failure aborts the run
without touching existing topic semantics.

### Layer 3 — Rules

A pure function with no network and no LLM. This is the cheapest layer and the
easiest to test.

Steps in order:

1. Normalize: trim, collapse whitespace, lowercase, unify ё/е.
2. Deduplicate, keeping the highest frequency for duplicates.
3. Drop queries matching the minus-word reference list.
4. Drop queries with frequency below the threshold. Default: 10.
5. Sort by frequency descending and keep the top 100.

The top-100 cut runs after the rules, not before. High-frequency academic queries
would otherwise consume slots and leave the final core much smaller than 100.

### Layer 4 — Relevance

Extends the existing `SemanticAgentAnalyzer`, narrowed to relevance only.

Additions to the current prompt:

- Reject academic and textbook phrasing.
- Reject queries whose intent does not match the article type.
- Return 10 additional long-tail queries of 3-7 words that the target audience
  would plausibly search.

Long-tail additions have no Wordstat frequency. They are stored with
`frequency: nil` and marked as agent-generated so the funnel can distinguish
them from pulled queries.

### Layer 5 — Cannibalization

Moves out of `SemanticAgentAnalyzer` into its own service. Same behavior as
today: compare survivors against the `PublishedSitePage` index for
`hadassah.moscow` and return risk, URL, and title.

Splitting it keeps each prompt focused and stops cannibalization accuracy from
degrading as the relevance prompt grows.

## Data Model

### New: SemanticFunnelEntry

A lightweight run journal. The raw Wordstat pool can reach several hundred
phrases per topic; storing all of them as `SemanticKeyword` would inflate the
database and blur what that model means.

Fields:

- `uuid: UUID`
- `text: String`
- `frequency: Int?`
- `layerRaw: String` — where it was dropped, or that it survived
- `reason: String` — short human-readable explanation
- `runID: UUID` — groups one collection run
- `createdAt: Date`
- relationship to `Topic`

Layer enum: `raw`, `droppedByRules`, `droppedByRelevance`,
`droppedByCannibalization`, `survived`.

Old runs can be deleted without affecting topic semantics.

### Changed: SemanticKeyword

No structural change is required. Two behavioral changes:

- `frequency` starts being populated from Wordstat instead of staying `nil`.
- Survivors are written with `userDecision: .accepted` rather than `.pending`.

`SemanticPromptRenderer` and the semantics table keep working unchanged.

### New: SemanticStopWord and SemanticQueryMask

Two reference lists, following the existing `ForbiddenPhrase` and
`EditorDictionary` model-plus-seeder pattern.

Fields for both: `uuid`, `text`, `isEnabled`, `createdAt`, `updatedAt`.

Seeded defaults for minus-words target medical academic and student queries:
реферат, курсовая, презентация, диссертация, патогенез, этиология, классификация,
мкб, тест, задача, лекция.

Seeded defaults for masks come from the methodology list: как, где, зачем, что,
сколько, почему, куда, кто, чей, когда, какой, какая, какое, какие, который.

## UI Design

### Funnel screen

Replaces `SemanticAgentSheet`. Shows the run as a vertical funnel: one row per
layer with the count that entered, the count that left, and an expandable list of
dropped queries with frequency and reason.

The final section lists survivors with frequency, and marks long-tail additions
generated by the agent.

Actions: re-run collection, open the semantics table, close.

Labels stay short and Russian. Raw enum names are never shown.

### Templates

Two new lists in the Templates section for minus-words and question masks, with
add, edit, enable/disable, and delete. The primary entry point is the funnel
screen: seeing junk in the funnel should lead directly to adding a minus-word
that applies to all future topics.

## Defaults

Confirmed with the user:

- Wordstat region: Moscow and Moscow region.
- Wordstat devices: all.
- Frequency threshold: 10.
- Top-100 cut applies after the rule layer.
- Re-running collection never removes or overwrites queries the user added or
  edited manually; it only adds new ones and updates frequencies.

## Error Handling

- Missing OpenAI key or Wordstat credentials: name which key is missing and point
  to settings.
- Wordstat quota exceeded: stop, keep existing semantics, and report clearly.
- Partial Wordstat failure: continue and list failed seeds in the funnel.
- Malformed LLM JSON at any layer: abort that layer with a retry message rather
  than guessing.
- Empty published-page index: warn that cannibalization checking is incomplete,
  as today.
- Empty result after all layers: keep existing semantics untouched and explain
  which layer emptied the list.

## Testing Strategy

Unit tests, all offline:

- `SemanticRuleFilter`: normalization, ё/е unification, duplicate merge keeping
  the higher frequency, minus-word removal, threshold, and top-100 cut ordering.
- Cut order: an academic high-frequency query is removed before the cut, and the
  survivor count reaches 100 when enough candidates exist.
- `WordstatResponseParser`: valid fixtures parse; malformed input throws.
- Seed plan parser: valid JSON parses; malformed JSON throws.
- Long-tail additions are stored with `frequency: nil` and marked as generated.
- Re-run does not overwrite manually edited keywords.
- Funnel entries record the correct layer and reason for each drop.

Manual checks:

- Full run on a real topic; verify funnel counts add up.
- Confirm frequencies appear in the semantics table.
- Add a minus-word from the funnel and re-run; the query disappears.

Test runs happen via Cmd+U in Xcode. The `xcodebuild test` runner hangs in this
environment; CLI verification is limited to `build-for-testing`.

## Risks

- **Wordstat API shape is unverified.** Authorization, quotas, and response
  format must be checked against current documentation before implementation.
  If the free tier turns out to be too restrictive, the design returns to the
  user before any code is written. The provider-function boundary limits the
  blast radius of whatever the API turns out to be.
- **SwiftData migration.** One new model plus two reference models. The existing
  database must open without data loss.
- **Token cost.** Bounded by the top-100 cut before the first large LLM call.
- **Automatic acceptance.** Survivors land as `accepted` without review. The
  funnel is the safeguard; if it proves too weak in practice, the fallback is to
  save survivors as `pending` again.
- **Reference lists drift.** Minus-words are global. A word that helps one topic
  can silently remove useful queries on another. The funnel makes this visible.

## Open Questions

- Exact Wordstat API endpoint, auth flow, and quota, to be confirmed from
  documentation at the start of implementation.

## Future Work

- Clustering and Yandex/Google SERP comparison from the methodology.
- Per-topic overrides for region and frequency threshold.
- Suggesting minus-words from funnel history.
- Reusing the funnel journal to compare collection runs over time.
