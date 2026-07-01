# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: planning

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

unknown

## Done criteria

- Design/spec is approved before coding.
- Semantic collection can import/query Wordstat through the chosen API path.
- Junk queries are filtered with explainable reasons.
- Cannibalization risks are detected against existing topics.
- UI lets the user review recommended include/exclude lists and decide what to accept.
- Existing topics keep their semantic queries after any migration.

## Agent handoff

Last agent: Codex

What changed: created branch `codex/semantic-wordstat-agent`; promoted semantic future task into current task memory.

Open risks: likely SwiftData schema migration; external Wordstat API/provider choice; API credentials and rate limits; cannibalization rules may need product decisions.

Next agent should check: use `docs/superpowers/plans/2026-07-02-semantic-agent.md` and choose subagent-driven or inline execution before touching implementation code.
