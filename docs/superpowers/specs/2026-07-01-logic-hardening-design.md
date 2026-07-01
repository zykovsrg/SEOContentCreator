# Logic Hardening Design

Date: 2026-07-01

## Goal

Make the current SEOContentCreator workflow safer around destructive actions,
incomplete brief data, pending generated text, and Google Docs publication.

## Scope

This change covers five audit findings:

1. Safer Google Docs overwrite.
2. Draft generation blocked until the topic has a title and direction.
3. Explicit pending state for newly generated versions.
4. Confirmation before deleting topics or knowledge-base nodes.
5. Explicit document choice before overwriting a previous Google Docs publication.

No broad UI redesign, queue/automation work, or unrelated refactoring is included.

## Design

### Google Docs overwrite

Overwrite must not clear an existing Google Doc and then leave it empty if the
insert step fails. The publisher should build one Google Docs `batchUpdate`
request list that deletes the existing body range and inserts the new document
content in the same API call.

The app still records a publication only after the API call succeeds.

### Required brief before draft

`BriefValidation.canStartDraft(title:hasDirection:)` is the source of truth for
starting the draft stage. `TopicWorkspaceView` must check this before running
`.draft`. If validation fails, it should show a plain Russian error message and
skip the OpenAI request.

Other stages keep their current flexible behavior.

### Pending generated versions

Add an explicit lightweight status to `ArticleVersion`:

- `pending` for newly generated versions waiting for user choice;
- `accepted` for current/accepted versions;
- `rejected` for generated results the user rejected;
- `archived` for versions hidden from normal version views.

Existing stored versions should behave as `accepted` by default. Rejection should
set the generated version to `rejected` instead of relying only on `isArchived`.
The version lane should show accepted versions and hide pending/rejected/archived
versions unless a future task adds a dedicated recovery view.

`isArchived` stays in the model for compatibility, but UI filtering should use
the new status where possible.

### Deletion confirmations

Deleting a topic or a knowledge-base node requires confirmation. The dialog text
should be clear for a non-technical editor. Knowledge-base deletion should warn
when the selected node is used by any topic as direction, doctor, or attached
knowledge.

The deletion itself remains a hard delete for this slice. Soft-delete/trash is a
future improvement, not part of this change.

### Publication document choice

When a topic has previous publications and the user chooses overwrite,
`PublishSheet` should make the target document explicit. The default can remain
the latest publication, but the user must be able to pick another previous
document before confirming overwrite.

If no previous publication exists, overwrite still falls back to creating a new
document as today.

## Data Model

`ArticleVersion` gets a new optional/raw string status field with a computed enum
wrapper. It is additive, so old local data should migrate lightly. Old versions
with an empty/missing status are treated as accepted.

## Testing

Add or update focused unit tests:

- `ArticlePublisherTests`: overwrite sends one replacement batch and does not
  record a publication when the replacement batch fails.
- `BriefValidationTests` or a small helper test: draft validation remains title
  plus direction.
- `ArticleVersionTests`: default status is accepted, pending/rejected/archive
  transitions are represented correctly.
- `VersionLane`/selection logic tests if filtering is extracted to a helper.

Manual checks after tests:

- Try draft generation on a topic without direction and confirm no request runs.
- Try deleting a topic and a knowledge-base node and confirm dialogs appear.
- Open publication sheet for a topic with multiple publications and confirm the
  overwrite target is selectable.

## Risks

The main risk is the additive SwiftData change on `ArticleVersion`. It should be
kept optional/backward-compatible and covered by tests. Google Docs overwrite is
also high-impact because it touches an external document; the change should be
tested with a fake `DocsPublishing` client before any real manual smoke test.
