# Current Task

Status: review

Allowed statuses: empty / active / review / blocked / done / paused

Stage: review

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Доработать этап Семантики: AI-агент через API получает запросы из Wordstat, фильтрует мусорные запросы, проверяет потенциальную каннибализацию с другими темами и готовит два списка для решения пользователя: рекомендуемые к включению по теме и не рекомендуемые к включению.

## Use Superpowers

yes

## Spec

Promoted from `FT-20260623-001 — Полноценная Семантика: частотность, статусы, индикатор`.

Design spec: `docs/superpowers/specs/2026-07-02-semantic-agent-design.md`.

Implementation plan: `docs/superpowers/plans/2026-07-02-semantic-agent.md`.

Initial scope to design through Superpowers before implementation:

- Keep the user in control: agent recommendations must be reviewable and manually accepted/rejected.
- Wordstat/API integration must be clarified before coding: provider, credentials, limits, error handling, and legal/usage constraints.
- Semantic output should support at least two recommendation buckets: include and exclude.
- Cannibalization check should compare candidate queries against existing topics before recommending inclusion.
- Existing semantic data must not be lost.

## Relevant files

- `docs/superpowers/specs/2026-07-02-semantic-agent-design.md`
- `docs/superpowers/plans/2026-07-02-semantic-agent.md`
- `SEOContentCreator/SEOContentCreator/Models/SemanticKeyword.swift`
- `SEOContentCreator/SEOContentCreator/Models/PublishedSitePage.swift`
- `SEOContentCreator/SEOContentCreator/Views/SemanticsEditorSheet.swift`
- `SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift`

## Done criteria

- Design/spec is approved before coding.
- Semantic collection can import/query Wordstat through the chosen API path.
- Junk queries are filtered with explainable reasons.
- Cannibalization risks are detected against existing topics.
- UI lets the user review recommended include/exclude lists and decide what to accept.
- Existing topics keep their semantic queries after any migration.

## Agent handoff

Last agent: Claude Code

What changed: implemented all 12 tasks of the semantic agent plan — `SemanticKeyword`/`PublishedSitePage` models with legacy `Topic.semantics` fallback, prompt renderer, mock query collector, OpenAI-based `SemanticAgentAnalyzer`, response parser, site page indexer (sitemap + HTML parsing), decision-table UI (`SemanticsEditorSheet`), `SemanticAgentSheet` for running collection/analysis, manual site index refresh wired to `SitePageIndexer`, and all affected test `ModelContainer`s updated to register the two new models. Full automated test suite passes (`xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS'` → TEST SUCCEEDED, no failures).

Open risks: real Wordstat API remains future work (current collector is a deterministic mock); live site refresh depends on hadassah.moscow availability; OpenAI output is strictly parsed JSON and may need retry on malformed responses.

Manual verification of the new mechanic (opening a topic, running the agent, reviewing include/exclude decisions, refreshing the site index in the running app) was intentionally NOT done in this session — moved to `ai/future-tasks.md` as a separate future task per user instruction, so it does not block closing this implementation task.

Next agent should check: nothing pending for this task; `task-finish` cleanup already applied.
