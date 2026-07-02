# Semantic Agent Design

Date: 2026-07-02

Status: draft for user review

Branch: `codex/semantic-wordstat-agent`

## Goal

Improve the Semantics stage from a plain line-based text editor into a reviewable semantic keyword workflow.

The first implementation deliberately avoids real Wordstat integration. It uses mock keyword collection inside the app, then sends those candidate queries to the existing OpenAI API path for analysis. The agent recommends which queries should be included or excluded, checks cannibalization against published pages on `hadassah.moscow`, and leaves the final decision to the user.

## Confirmed Scope

In scope:

- Replace the user-facing semantics editor with a keyword decision table.
- Preserve existing `Topic.semantics: [String]` values by migrating or backfilling them into semantic keyword records.
- Generate mock candidate queries for the current topic inside the app.
- Analyze candidate queries with OpenAI.
- Store all results: accepted, rejected, and pending decisions.
- Keep user control: agent output is a recommendation, not an automatic final decision.
- Add a local published-page index for `hadassah.moscow`.
- Update the site index only when the user explicitly presses an update button.
- Store indexed page fields: URL, title, meta description, H1, and H2 headings.
- Check cannibalization against the published-page index.
- Show cannibalization page, explanation, and risk level: low, medium, or high.
- Include only accepted and required keywords in `{{семантика}}`.

Out of scope for this first implementation:

- Real Wordstat API integration.
- Manual paste/import of Wordstat exports.
- Automatic background site-index refresh.
- Full-page text extraction for the site index.
- A separate advanced site-index management screen with history.
- Topvisor import.

## Product Flow

1. The user opens a topic and clicks Semantics.
2. The Semantics sheet shows a table of saved keyword decisions.
3. The user can manually refresh the `hadassah.moscow` published-page index.
4. The user opens a separate Semantic Agent sheet.
5. The app generates mock candidate queries for the topic.
6. The user runs OpenAI analysis.
7. The agent returns recommended include and exclude lists with reasons.
8. The user saves the agent result into the topic as pending decisions.
9. In the main Semantics table, the user accepts, rejects, marks required, or leaves each query pending.
10. Generation prompts receive only accepted and required semantic keywords.

## Data Model

### Semantic Keyword

Add a SwiftData model, tentatively named `SemanticKeyword`.

Fields:

- `uuid: UUID`
- `text: String`
- `frequency: Int?`
- `agentRecommendationRaw: String`
- `userDecisionRaw: String`
- `reasonCategoryRaw: String`
- `explanation: String`
- `cannibalizationRiskRaw: String`
- `cannibalizationURL: String?`
- `cannibalizationTitle: String?`
- `createdAt: Date`
- `updatedAt: Date`
- relationship to `Topic`

Enums:

- Agent recommendation: `include`, `exclude`, `none`
- User decision: `pending`, `accepted`, `rejected`, `required`
- Reason category: `none`, `junk`, `offTopic`, `cannibalization`, `lowQuality`, `tooBroad`, `wrongIntent`, `other`
- Cannibalization risk: `none`, `low`, `medium`, `high`

Existing line-based semantics should be preserved. Existing strings are converted or backfilled as semantic keyword records with:

- user decision: `accepted`
- agent recommendation: `none`
- empty explanation
- no cannibalization risk

Migration rule: do not delete or clear the legacy `Topic.semantics` values during the first implementation step. The new UI should write to semantic keyword records. Prompt rendering should prefer semantic keyword records, and may fall back to legacy strings only when no records exist yet. A later cleanup can remove the legacy field after the migration is proven safe.

### Published Site Page

Add a SwiftData model, tentatively named `PublishedSitePage`.

Fields:

- `uuid: UUID`
- `url: String`
- `title: String`
- `metaDescription: String`
- `h1: [String]`
- `h2: [String]`
- `siteHost: String`
- `indexedAt: Date`

For this task, `siteHost` is expected to be `hadassah.moscow`.

## UI Design

### Semantics Sheet

Replace the current plain `TextEditor` with a table.

Main columns:

- Query
- Frequency
- Agent recommendation
- User decision
- Reason
- Cannibalization risk
- Published page

Top actions:

- Semantic Agent: opens the agent collection sheet.
- Refresh site pages: updates the `hadassah.moscow` index manually.
- Filter: all, pending, accepted, rejected, recommended include, recommended exclude.
- Accept selected.
- Reject selected.

The sheet should remain understandable for a non-technical user. Use short Russian labels and avoid exposing raw enum names.

### Semantic Agent Sheet

This is a separate sheet opened from Semantics.

Steps:

1. Show the current topic title.
2. Generate mock candidate queries.
3. Run OpenAI analysis.
4. Show two sections:
   - recommended to include;
   - not recommended to include.
5. Show category, short explanation, cannibalization risk, and matching published page when present.
6. Save results to the topic as pending decisions.

If the site index is empty or old, show a warning that cannibalization checking may be incomplete.

## Services And Logic

### Mock Candidate Collector

Add a deterministic mock collector for the first implementation. It generates a stable list of candidate queries from the topic title and article type. This makes the UI and tests predictable while Wordstat remains out of scope.

### Site Indexer

Add a service that refreshes published pages from `hadassah.moscow` only when the user presses the update button.

The service should:

- prefer sitemap discovery when available;
- fetch public HTML pages only;
- extract URL, title, meta description, H1, and H2;
- replace or upsert the local page index for `hadassah.moscow`;
- report partial failures without deleting the last usable index.

If network refresh fails, the user can continue with the existing index.

### Semantic Agent Analyzer

Add an analyzer that sends OpenAI:

- topic title;
- article type;
- candidate queries;
- indexed published-page summaries.

The response must be structured JSON. The app should reject malformed responses with a clear error instead of guessing.

Required output per keyword:

- query text;
- frequency when known;
- recommended bucket: include or exclude;
- reason category;
- short explanation;
- cannibalization risk;
- cannibalization URL and title when applicable.

### Prompt Rendering

Update `PromptBuilder` so `{{семантика}}` is rendered from semantic keyword records, not from all saved decisions.

Include:

- accepted keywords;
- required keywords, clearly marked as required.

Exclude:

- pending keywords;
- rejected keywords;
- agent recommendations not yet accepted by the user.

## Error Handling

User-facing errors should be simple:

- Missing OpenAI key: ask the user to add the key in settings.
- Empty site index: explain that cannibalization checking may be incomplete.
- Site refresh failed: keep the old index and let the user continue.
- OpenAI response is malformed: ask the user to retry.
- Duplicate keyword: merge or update the existing row instead of creating noisy duplicates.

## Testing Strategy

Unit tests:

- Existing line-based semantics are preserved as accepted semantic keywords.
- `{{семантика}}` includes only accepted and required keywords.
- Pending and rejected keywords do not appear in prompts.
- Required keywords are rendered distinctly.
- OpenAI response parser accepts valid JSON and rejects malformed JSON.
- Cannibalization data stores URL, explanation, and risk.
- Mock candidate collector returns stable data.
- Duplicate candidate queries are merged safely.

Integration or focused UI tests where practical:

- Semantics sheet can display accepted, rejected, and pending rows.
- Agent result can be saved as pending decisions.
- Site-index refresh failure does not erase the existing index.

Manual checks:

- Run a sample topic through mock collection and OpenAI analysis.
- Refresh `hadassah.moscow` index from the app.
- Confirm the user can accept/reject recommendations and prompt rendering changes accordingly.

## Risks

- SwiftData schema change: adding models and moving from `[String]` semantics to related records can affect existing user data. The implementation must preserve old strings.
- Network and parsing variability: `hadassah.moscow` sitemap or HTML can change. The first version should handle partial failures calmly.
- OpenAI output variability: strict JSON parsing and retry-friendly errors are required.
- Cost and latency: OpenAI analysis should be user-triggered, not automatic.
- Cannibalization is advisory: the UI must present risk as a recommendation, not an absolute rule.

## Future Work

- Real Wordstat API provider.
- Manual paste/import from Wordstat export.
- Advanced site-index management screen with refresh history.
- Full-page text extraction if title/description/H1/H2 is not enough.
- Optional automatic index refresh.
- More advanced semantic grouping.
