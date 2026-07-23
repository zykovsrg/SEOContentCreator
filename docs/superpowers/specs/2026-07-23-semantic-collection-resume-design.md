# Semantic Collection Resume + Stop-on-Wordstat-Error Design

Date: 2026-07-23

Status: draft for user review

Builds on `2026-07-22-semantic-autocollection-design.md` and the crash fix
recorded in `ai/changelog.md` (2026-07-23, "Исправлен краш при сохранении
большого журнала Wordstat").

## Goal

`SemanticCollectionRunner.run` currently has two related weaknesses on large
seed sets (observed live: 2160 seed phrases):

1. Every error from `pullPhrases` (network drop, Wordstat/Yandex API error) is
   caught per-seed and swallowed — the loop just keeps going to the next
   seed. In practice `pullPhrases` can only ever throw when Wordstat itself
   failed to answer (confirmed by reading `WordstatCloudClient` and
   `WordstatResponseParser`: a legitimately empty result decodes as an empty
   array, never a thrown error), so this silent continuation burns through
   the remaining seeds against an API that is already unreachable.
2. All progress (seed plan, which seeds succeeded, what Wordstat returned) is
   held only in the local `pulled` array for the lifetime of one `run()`
   call. A dropped connection, a Wordstat error, or quitting the app loses
   all of it — the next attempt re-runs AI seed planning and re-pulls every
   seed from zero, even the ones that already succeeded.

This design makes any Wordstat-level failure stop the whole run immediately,
and makes stopped/interrupted progress resumable, with an explicit way to
discard it and start over.

## Confirmed Scope

In scope:

- A new SwiftData checkpoint model holding the seed plan, which seeds are
  already done, and the Wordstat results gathered so far, one-to-one with
  `Topic`.
- Changing the Wordstat seed loop in `SemanticCollectionRunner.run` to abort
  the whole run on any non-cancellation error from `pullPhrases`, instead of
  logging it in the funnel journal and continuing to the next seed.
- Resuming a run reuses the same `runID`, the persisted seed plan, and the
  settings (stop-words/masks/threshold/limit) captured at the *first*
  attempt — later edits to those settings only apply to a fresh run, not to
  a resumed one.
- `SemanticFunnelView` shows a resume affordance ("Продолжить сбор" +
  separate "Сбросить") when a checkpoint exists for the topic, and a
  distinct message when a run auto-stops on a Wordstat error vs. a manual
  stop.
- The checkpoint is deleted automatically when a run completes successfully,
  or explicitly via the reset action.

Out of scope:

- Changing behavior of the AI seed-planning, relevance, or cannibalization
  steps — they already abort the whole run on error today (no
  catch-and-continue there), so nothing changes for them.
- Deleting or touching old funnel journal entries left behind by an
  abandoned run (harmless: `SemanticFunnelView` only ever displays entries
  for the `runID` held in its own `@State`, which resets when the window is
  reopened).
- Any change to Wordstat rate limiting, request batching, or the 10-minute
  overall deadline (`SemanticCollectionDeadline`).
- Rotating the previously-exposed Wordstat key (separate, already-tracked
  open risk, unrelated to this work).

## Data Model

New model, alongside `ReaderIntent` in `Topic`'s relationships:

```swift
@Model
final class SemanticCollectionCheckpoint {
    var uuid: UUID
    var runID: UUID
    var seeds: [String]              // full seed plan from the AI planner
    var completedSeeds: [String]     // seeds successfully pulled so far
    var pulled: [WordstatPhrase]     // accumulated raw Wordstat results
    var stopWordsSnapshot: [String]  // settings frozen at the first attempt
    var masksSnapshot: [String]
    var thresholdSnapshot: Int
    var limitSnapshot: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship var topic: Topic?
}
```

`Topic` gets:

```swift
@Relationship(deleteRule: .cascade, inverse: \SemanticCollectionCheckpoint.topic)
var collectionCheckpoint: SemanticCollectionCheckpoint?
```

`WordstatPhrase` (`Logic/WordstatProvider.swift`) gains `Codable` conformance
so SwiftData can persist `[WordstatPhrase]` as a plain attribute — no child
model needed.

## Runner Behavior

`SemanticCollectionRunner.run` gains an optional resume path:

1. **Start of run:** if `topic.collectionCheckpoint` exists, reuse its
   `runID`, `seeds` (skip AI seed planning entirely), `pulled`, and
   `completedSeeds`. The caller (the view) constructs the runner itself with
   `stopWordsSnapshot`/`masksSnapshot`/`thresholdSnapshot`/`limitSnapshot`
   from the checkpoint instead of the topic's current settings, so a resumed
   run is internally consistent even if the user edited stop-words/masks in
   between.
2. **No checkpoint:** behave as today (fresh `runID`, call the AI planner),
   but create the checkpoint immediately after planning succeeds — before
   the first Wordstat call — with `completedSeeds: []` and `pulled: []`, so
   even a failure on the very first seed leaves something to resume from.
3. **Seed loop:** for each seed not yet in `completedSeeds`:
   - on success — append results to `pulled`, add the seed to
     `completedSeeds`, persist the checkpoint (cheap: a handful of scalars
     and strings, not the funnel journal).
   - on `CancellationError` — propagate as today; the checkpoint is left in
     place (a manual stop is resumable too).
   - on any other error — record it in the funnel journal exactly as today
     (for visibility in the funnel screen), **then rethrow instead of
     continuing the loop**. The checkpoint is left in place.
4. **Successful completion:** after the existing final `saveContext(context)`
   call succeeds, delete `topic.collectionCheckpoint`.
5. **Explicit reset:** a new small helper (called from the view, not from
   `run`) deletes the checkpoint for a topic. It does not touch the funnel
   journal or semantic keywords.

No change to the AI planning / relevance / cannibalization steps: they
already propagate errors directly (no catch-and-continue), so a failure
there aborts the run today and continues to do so; on the next attempt, the
checkpoint (already holding all of `pulled`) lets the run skip straight past
the Wordstat stage without re-contacting Wordstat.

## UI (`SemanticFunnelView`)

- On appear, read `topic.collectionCheckpoint`.
- If present: the primary button reads **"Продолжить сбор"** instead of
  "Собрать семантику"; a separate **"Сбросить"** button sits next to it
  (visually distinct from the destructive "Остановить" that only appears
  while a run is active). A short line under the buttons shows progress,
  e.g. "Прошлый сбор остановлен: 12 из 2160 запросов получено."
- "Продолжить сбор" calls the same `collect()` path; the runner is built
  with the checkpoint's frozen settings when a checkpoint exists.
- "Сбросить" asks for confirmation (irreversible — discards saved progress),
  then deletes the checkpoint; the button reverts to "Собрать семантику".
- When a run stops automatically because of a Wordstat error, `message`
  shows the error text plus a second line noting the progress is saved and
  can be resumed later — distinct from the existing manual-stop message
  ("Сбор остановлен. Семантика темы не изменена.").

## Testing

- Seed pull throws a Wordstat-style error → the whole run stops immediately
  (does not call `pullPhrases` for remaining seeds); a checkpoint exists
  afterwards containing the phrases pulled before the failure.
- Calling `run` again with an existing checkpoint skips seeds already in
  `completedSeeds` (does not call `pullPhrases` for them again).
- A successful run deletes the checkpoint.
- Explicit reset deletes the checkpoint; the next `run` starts fresh (new
  `runID`, full seed list, no leftover `pulled`).
- A resumed run uses the settings frozen in the checkpoint even if the
  stop-words/masks/threshold/limit passed to a fresh `SemanticCollectionRunner`
  differ.
- `recordsRealErrorMessageWhenASeedFails` (existing test) currently asserts
  the run *continues* after one seed's failure and later succeeds — this
  behavior is being deliberately removed, so the test must be rewritten to
  assert the run stops and the failure is the terminal error.

## Migration Note

Adding a new `@Model` and a new optional relationship on `Topic` is an
additive SwiftData schema change (matches how `ReaderIntent` was added
earlier) — existing topics simply have `collectionCheckpoint == nil` until
their next interrupted run. No destructive migration path.
