# Unified editor: merge manual edit + fragment edit

Status: approved
Date: 2026-07-04

## Problem

The app has two separate sheets for editing an article's current version:

- **`ManualEditSheet`** — a full-text Markdown editor (`MarkdownTextEditor`); saving
  creates one new `ArticleVersion` (`VersionActions.applyManualEdit`).
- **`FragmentEditSheet`** — paste/select a fragment into a text box, pick a skill
  preset or write a free-form comment, the AI rewrites just that fragment. The
  fragment is located in the full text by substring search (`FragmentSplicer`),
  which fails or is ambiguous when the fragment text repeats elsewhere in the
  article. Every accepted fragment immediately creates its own `ArticleVersion`
  and closes the sheet.

The user wants one editor: freely edit the full text and, without leaving the
screen, regenerate a selected fragment via a skill preset or a custom comment,
repeating this any number of times before saving once.

## UX flow

One toolbar button, **"Редактор"** (pencil icon), replaces the two existing
buttons ("Ручная правка", "Правка фрагмента") in `TopicWorkspaceView`.

1. Opens a full-size Markdown text editor pre-filled with the current version's
   text. Freely editable, same keyboard shortcuts as today's `MarkdownTextEditor`
   (Cmd+B/I, Cmd+Option+1/2/3).
2. Selecting text with the mouse shows a floating **"✨ Переписать"** button
   above the selection. A toolbar button, **"Перегенерировать выделенное"**,
   does the same thing and is enabled only when the selection is non-empty and
   no fragment operation is in flight. Either entry point opens the same popover.
3. The popover mirrors `FragmentEditSheet`'s input form minus the "Фрагмент"
   text box (the selection *is* the fragment now, so no clipboard paste step):
   a segmented picker (Скилл / Свой комментарий), the skill list or a comment
   `TextEditor`, and a "Перегенерировать" button.
4. While generating, the whole editor is temporarily read-only (`isEditable =
   false`). No parallel fragment requests — one active request at a time.
5. When generation finishes, the selected range's displayed text is replaced by
   the AI's rewritten fragment with a highlight (diff-style background), and a
   fixed **Принять / Отклонить** bar appears (bottom/top of the sheet). The
   editor stays read-only until this specific fragment's fate is decided.
6. **Принять** — the new fragment text stays in place, highlight clears, editor
   becomes editable again; the user can keep typing and/or select another
   fragment (still one active request at a time; no queueing).
   **Отклонить** — reverts to the original fragment text, same re-enable.
7. **Сохранить** — commits the *entire* current editor text (manual edits +
   every accepted fragment since opening) as a single new `ArticleVersion` via
   the existing `VersionActions.applyManualEdit(topic:newText:in:)` (source:
   `.manualEdit`). **Отмена** discards everything and dismisses without saving.
   Both are disabled while a fragment operation is generating or awaiting
   accept/reject — the user must resolve it first. Cancel is otherwise always
   available.

## Architecture

**Key simplification.** Today's fragment lookup is search-by-substring
(`FragmentSplicer`), which is why "fragment not found" / "fragment occurs N
times" errors exist — the fragment text may repeat elsewhere in the article.
In the unified editor the fragment *is* an actual text-view selection, so its
exact range is always known. Splicing becomes a direct range replacement, and
the not-found/ambiguous error class disappears entirely by construction.

### New/changed files

- **`Views/EditorSheet.swift`** (new) — replaces `ManualEditSheet.swift` and
  `FragmentEditSheet.swift`. Owns the full text (`@State text: String`), the
  session state (see below), the popover (mode picker + skill list/comment
  field), the Принять/Отклонить bar, and Отмена/Сохранить.
- **`Views/MarkdownTextEditor.swift`** — extended to also:
  1. report the current selection (range + its on-screen rect, for floating
     button placement) via a delegate callback / binding;
  2. accept a binding/flag to toggle `isEditable` for the read-only phases;
  3. temporarily highlight an arbitrary range using
     `NSLayoutManager.addTemporaryAttribute` — non-destructive, the stored
     string stays plain Markdown text (no `AttributedString` conversion, per
     the existing doc comment on this file).
- **`Logic/FragmentEditor.swift`** — simplified: drops `accept(topic:in:)` (no
  longer creates an `ArticleVersion` itself — that only happens once, from
  `EditorSheet`'s Сохранить) and drops the `FragmentSplicer` call (the caller
  already knows the exact range and substitutes the rewritten text into it
  directly). Prompt building, streaming, `GenerationJob` bookkeeping, and role
  lookup are unchanged.
- **`Logic/FragmentSplicer.swift`** — deleted (with `FragmentSplicerTests`).
- **`Logic/EditorSessionState.swift`** (new) — small pure type modeling the
  three-state session (`editing` / `generating(range)` /
  `reviewing(range, proposedText)`) and the derived rules: can a regenerate be
  triggered (needs `editing` + non-empty selection), can Save/Cancel-that-keeps-
  changes proceed, is the editor currently read-only. Testable in isolation,
  following the project's existing pattern of extracting view-logic decisions
  into small pure types (`WorkspaceLayout`, `StageRunGuard`).
- **`Views/TopicWorkspaceView.swift`** — `showManualEdit`/`showFragmentEdit` and
  their two toolbar buttons collapse into one `showEditor` + one "Редактор"
  toolbar button (pencil icon), opening `EditorSheet(topic: topic)`.

No SwiftData schema changes: saving still produces exactly one `ArticleVersion`
through the existing `VersionActions.applyManualEdit`, so there is no migration
risk.

## Error handling

- Missing API key / token-limit truncation: same messages as today.
- Both regenerate entry points (floating button, toolbar button) disabled with
  an empty selection or while another fragment operation is in flight.
- Сохранить/Отмена disabled while a fragment is generating or awaiting
  accept/reject; Отмена is otherwise always available and discards all local
  changes (manual edits and any already-accepted fragments) without creating a
  version.
- The "fragment not found" / "fragment occurs N times" error class is removed
  by construction (see Architecture).
- Not addressed in this task (pre-existing behavior, carried over unchanged):
  there is no explicit way to cancel a fragment regeneration once started —
  same as today's `FragmentEditSheet`. Can be filed as a future task if it
  becomes a problem.

## Testing plan

- `Logic/EditorSessionState.swift` gets unit tests covering state transitions
  and the derived can-regenerate / can-save / is-read-only rules.
- `FragmentEditorTests` updated: remove the `ambiguous`/`notFound` cases (the
  scenario no longer exists); replace the `accept()`-creates-a-version test
  with a test that `FragmentEditor` just returns the rewritten fragment text,
  since splicing and version creation move to `EditorSheet`.
- `FragmentSplicerTests` deleted along with `FragmentSplicer.swift`.
- The AppKit-level selection/highlight/floating-button wiring in
  `MarkdownTextEditor` is not unit-tested, consistent with that file's existing
  (untested) keyboard-shortcut logic — covered by the manual checklist instead.
- Manual QA checklist (interactive UI feature):
  1. Select a fragment → floating "✨ Переписать" appears; the toolbar button
     does the same thing.
  2. Regenerate via a skill preset; regenerate via a custom comment.
  3. Принять a fragment, then Отклонить another, in the same session.
  4. Manually edit text before and after a fragment regeneration.
  5. Сохранить — confirm exactly one new `ArticleVersion` is created containing
     all manual edits and accepted fragments; Отмена — confirm nothing is
     saved.
  6. Regenerate a fragment whose text also appears elsewhere in the article —
     confirm the correct occurrence changes (this used to be the "ambiguous"
     failure case).
