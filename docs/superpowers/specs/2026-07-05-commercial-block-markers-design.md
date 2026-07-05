# Commercial block markers → bordered table on Google Docs publish

Status: approved
Date: 2026-07-05

## Problem

The user manually marks "commercial" sections of an article (a block about a
doctor/clinic, product recommendation, etc.) by inserting a 1×1 table in the
Google Doc and copying the block's text into that single cell — a way to
visually set commercial content apart from editorial content, done by hand
every time after publishing.

The app should do this automatically at publish time. To do that, the app
needs a way to know, in the article's Markdown text, where a commercial block
starts and ends.

## UX flow

1. In the "Редактор" screen, the user selects the text that makes up a
   commercial block (can span several paragraphs, lists — not necessarily a
   single paragraph) and either presses **Cmd+Shift+K** or clicks a new
   toolbar button ("Отметить как коммерческий блок") in `EditorSheet`. Both
   trigger the same action.
2. This wraps the selection with marker lines:
   ```
   [[БЛОК]]
   <selected text>
   [[/БЛОК]]
   ```
3. An article can contain any number of such marked blocks.
4. Markers are visible as plain text everywhere in the app today (workspace
   view, version comparison, etc.) — no special rendering in this iteration.
5. On publish to Google Docs (both "new document" and "overwrite" modes), each
   marked block becomes a 1×1 table with Google Docs' default border (the same
   look the user gets today from Insert → Table → 1×1) containing the block's
   text, formatted the same way as the rest of the document (bold, bullet/
   numbered lists). The `[[БЛОК]]`/`[[/БЛОК]]` marker lines themselves are
   stripped and never appear in the published document.

## Architecture

### New pure type: `Logic/CommercialBlockSplitter.swift`

```swift
struct TextSegment: Equatable {
    let isCommercial: Bool
    let text: String   // markers already stripped
}

enum CommercialBlockSplitter {
    static func split(_ markdown: String) -> [TextSegment]
}
```

Scans the raw Markdown text for `[[БЛОК]]` / `[[/БЛОК]]` pairs, in order, no
nesting. Produces an ordered list of segments alternating commercial/non-
commercial content (adjacent non-commercial text is merged into one segment;
adjacent commercial pairs are never merged — each `[[БЛОК]]`...`[[/БЛОК]]` pair
is its own segment). An unmatched marker (no matching close before the next
open marker or end of text) is **not** treated as an error: the literal marker
text is left in place inside a non-commercial segment, so no content is ever
silently dropped or a publish silently fails because of a typo/stray bracket.

### Publish pipeline changes

Today, `DocsRequestBuilder.build(blocks:)` does exactly one `insertText` for
the entire document (all blocks joined with `\n`), then walks a single cursor
to emit per-block `updateParagraphStyle` / `createParagraphBullets` /
`updateTextStyle` requests referencing offsets into that one big insert. This
doesn't extend to tables: inserting a table via the Google Docs API is a
distinct structural request (`insertTable`) that must be sequenced correctly
relative to surrounding `insertText` calls, not folded into one flat text
blob.

New flow, orchestrated by `ArticlePublisher`:

1. `CommercialBlockSplitter.split(text)` → `[TextSegment]`.
2. Each segment's text is parsed independently with the existing, unmodified
   `MarkdownDocParser.parse(_:) -> [DocBlock]`.
3. `DocsRequestBuilder` is restructured to walk segments in order, keeping one
   running document-index cursor across the whole call:
   - non-commercial segment: same per-block request generation as today
     (`insertText` for the segment's joined blocks, then paragraph style /
     list / bold requests), starting at the current cursor;
   - commercial segment: emit `insertTable` (1 row × 1 column) at the current
     cursor, then reuse the same per-block request generation for the
     segment's blocks, but targeting the table cell's content start index
     (current cursor + a fixed offset — see risk below) instead of the
     top-level body.
4. The whole result is still a single `[[String: Any]]` request array sent in
   one atomic `batchUpdate`, preserving the existing atomicity invariant
   (`ai/decisions.md`, 2026-07-01 — overwrite must be a single batchUpdate).
5. No extra `updateTableCellStyle` border request is issued — a freshly
   inserted 1×1 table already renders with Google Docs' default single-cell
   border, identical to the user's current manual workflow.

### Risk: table cell insertion offset

After `insertTable` places a table at document index `N`, the single cell's
paragraph content start index is expected to be `N + 4` (table, row, cell, and
an auto-created empty paragraph are structural elements ahead of the
insertion point) — a commonly reported behavior for 1×1 tables via the Google
Docs API, but not something this project has verified against a live document
(there is no existing automated live-API test; `ai/future-tasks.md` already
has a pending idea for one, `FT-20260701-001`). This offset is isolated as one
named constant so a wrong guess is a one-line fix, not a deep bug hunt, and
must be confirmed against a real test document as part of this task's manual
QA before considering it reliable.

## Editor changes

`MarkdownEditorTextView` (in `MarkdownTextEditor.swift`) already has
`wrapSelection(prefix:suffix:)`, used today for Cmd+B/Cmd+I. Add Cmd+Shift+K
calling `wrapSelection(prefix: "[[БЛОК]]\n", suffix: "\n[[/БЛОК]]")` (with
newlines so the block doesn't visually run into adjacent text). Expose a
public method the SwiftUI layer can call programmatically (the existing
keyboard-shortcut methods are private and only reachable via `keyDown`), so
`EditorSheet` can offer the same action from a toolbar button, not just the
shortcut.

## Testing plan

- `CommercialBlockSplitterTests` (new): single block, multiple blocks, no
  blocks, unmatched/stray marker (left as literal text), marker at start/end
  of text.
- `DocsRequestBuilderTests`: new cases covering a segment sequence that
  includes a commercial block — exact expected request shapes (`insertTable`,
  cell content requests, indices), using the isolated offset constant.
- `MarkdownDocParser` is unchanged — no new tests needed there.
- The AppKit keyboard-shortcut wiring (Cmd+Shift+K) is not unit-tested,
  consistent with the rest of `MarkdownEditorTextView` — covered by manual
  checklist.
- **Mandatory manual verification against a real Google Doc** (not just a
  build check): publish an article containing a commercial block through both
  "new document" and "overwrite" modes, and confirm the resulting Google Doc
  actually shows a correctly bordered 1×1 table with the right text in it, not
  shifted/broken indices.
