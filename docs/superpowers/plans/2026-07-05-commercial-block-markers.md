# Commercial Block Markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user mark a commercial section of an article in the "Редактор" screen with `[[БЛОК]]`/`[[/БЛОК]]` markers, and have it automatically become a bordered 1×1 table when the article is published to Google Docs.

**Architecture:** A new pure `CommercialBlockSplitter` splits the raw Markdown text into ordered commercial/non-commercial segments; `DocsRequestBuilder` is restructured to build Google Docs `batchUpdate` requests segment-by-segment, emitting an `insertTable` request (plus its cell content) for commercial segments instead of plain paragraphs, while staying a single atomic `batchUpdate` call. `MarkdownTextEditor` gets a new keyboard shortcut (Cmd+Shift+K) and a programmatic trigger so `EditorSheet` can offer the same action from a toolbar button.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSTextView`), Google Docs REST API (`batchUpdate`), Swift Testing (`@Test`/`#expect`).

**Design doc:** `docs/superpowers/specs/2026-07-05-commercial-block-markers-design.md`

---

## Task 1: `CommercialBlockSplitter` — pure text-splitting logic

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/CommercialBlockSplitter.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/CommercialBlockSplitterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SEOContentCreatorTests/CommercialBlockSplitterTests.swift` with this exact content:

```swift
import Testing
@testable import SEOContentCreator

struct CommercialBlockSplitterTests {
    @Test func noMarkersReturnsOneSegment() {
        let result = CommercialBlockSplitter.split("Обычный текст статьи.")
        #expect(result == [TextSegment(isCommercial: false, text: "Обычный текст статьи.")])
    }

    @Test func singleBlockInTheMiddle() {
        let text = "До блока.\n\n[[БЛОК]]\nТекст блока.\n[[/БЛОК]]\n\nПосле блока."
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [
            TextSegment(isCommercial: false, text: "До блока."),
            TextSegment(isCommercial: true, text: "Текст блока."),
            TextSegment(isCommercial: false, text: "После блока.")
        ])
    }

    @Test func multipleBlocks() {
        let text = "[[БЛОК]]\nПервый.\n[[/БЛОК]]\nМежду.\n[[БЛОК]]\nВторой.\n[[/БЛОК]]"
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [
            TextSegment(isCommercial: true, text: "Первый."),
            TextSegment(isCommercial: false, text: "Между."),
            TextSegment(isCommercial: true, text: "Второй.")
        ])
    }

    @Test func blockAtVeryStartAndEnd() {
        let text = "[[БЛОК]]\nС начала.\n[[/БЛОК]]"
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [TextSegment(isCommercial: true, text: "С начала.")])
    }

    @Test func unmatchedOpenMarkerIsKeptAsLiteralText() {
        let text = "Текст [[БЛОК]] без закрытия."
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [TextSegment(isCommercial: false, text: "Текст [[БЛОК]] без закрытия.")])
    }

    @Test func emptyTextReturnsNoSegments() {
        #expect(CommercialBlockSplitter.split("") == [])
    }

    @Test func whitespaceOnlyGapBetweenBlocksProducesNoSpuriousSegment() {
        let text = "[[БЛОК]]\nA.\n[[/БЛОК]]\n\n\n[[БЛОК]]\nB.\n[[/БЛОК]]"
        let result = CommercialBlockSplitter.split(text)
        #expect(result == [
            TextSegment(isCommercial: true, text: "A."),
            TextSegment(isCommercial: true, text: "B.")
        ])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: FAIL to compile — `CommercialBlockSplitter` and `TextSegment` don't exist yet.

- [ ] **Step 3: Write the implementation**

Create `SEOContentCreator/SEOContentCreator/Logic/CommercialBlockSplitter.swift` with this exact content:

```swift
import Foundation

/// One contiguous run of the article's Markdown text, tagged with whether it
/// falls inside a `[[БЛОК]]`...`[[/БЛОК]]` pair. Produced by
/// `CommercialBlockSplitter.split` for the publish pipeline to turn into a
/// bordered table (see `DocsRequestBuilder`).
struct TextSegment: Equatable {
    let isCommercial: Bool
    let text: String
}

/// Splits an article's raw Markdown text into ordered commercial/non-
/// commercial segments, using `[[БЛОК]]`/`[[/БЛОК]]` marker lines the user
/// inserts manually in the editor (see `MarkdownTextEditor`'s Cmd+Shift+K).
/// Markers are stripped from the returned segment text.
enum CommercialBlockSplitter {
    private static let openMarker = "[[БЛОК]]"
    private static let closeMarker = "[[/БЛОК]]"

    /// An unmatched `[[БЛОК]]` (no closing marker before the next opener or
    /// the end of the text) is never treated as an error: everything from
    /// that point on is kept as literal plain text, so a typo or stray
    /// bracket can never silently drop article content.
    static func split(_ markdown: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var plainBuffer = ""
        var remainder = Substring(markdown)

        while !remainder.isEmpty {
            guard let openRange = remainder.range(of: openMarker) else {
                plainBuffer += remainder
                remainder = ""
                break
            }
            guard let closeRange = remainder.range(of: closeMarker, range: openRange.upperBound..<remainder.endIndex) else {
                plainBuffer += remainder
                remainder = ""
                break
            }

            plainBuffer += remainder[remainder.startIndex..<openRange.lowerBound]
            appendPlainSegmentIfNeeded(&segments, &plainBuffer)

            let inner = remainder[openRange.upperBound..<closeRange.lowerBound]
            segments.append(TextSegment(isCommercial: true, text: trimNewlines(String(inner))))

            remainder = remainder[closeRange.upperBound...]
        }
        appendPlainSegmentIfNeeded(&segments, &plainBuffer)

        return segments
    }

    private static func appendPlainSegmentIfNeeded(_ segments: inout [TextSegment], _ plainBuffer: inout String) {
        let trimmed = trimNewlines(plainBuffer)
        if !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(TextSegment(isCommercial: false, text: trimmed))
        }
        plainBuffer = ""
    }

    private static func trimNewlines(_ s: String) -> String {
        var result = Substring(s)
        while result.first == "\n" { result = result.dropFirst() }
        while result.last == "\n" { result = result.dropLast() }
        return String(result)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`. Then run the new tests via Cmd+U in Xcode (this project's `xcodebuild test` CLI is known to hang — see `ai/architecture.md`/project memory — use `build-for-testing` for CLI compile checks only) and confirm all 7 `CommercialBlockSplitterTests` pass.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/CommercialBlockSplitter.swift SEOContentCreator/SEOContentCreatorTests/CommercialBlockSplitterTests.swift
git commit -m "Add CommercialBlockSplitter for [[БЛОК]] marker parsing"
```

---

## Task 2: `DocsRequestBuilder` — segment-aware request building with tables

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/DocsRequestBuilderTests.swift`

**Context:** Today `DocsRequestBuilder.build(blocks: [DocBlock])` builds one `insertText` for the whole document plus per-block style/list/bold requests, referencing offsets computed by walking a single cursor starting at index 1. This task adds a `DocSegment` type (a run of `[DocBlock]` tagged `isCommercial`) and a new `build(segments:)` that keeps the exact same behavior for non-commercial segments, but emits an `insertTable` (1×1) request for commercial segments, followed by the same paragraph/list/bold request logic targeting the table cell's content instead of the top-level body. The existing `build(blocks:)` and `buildReplacingBody(blocks:existingBodyEndIndex:)` become thin wrappers around the new segment-based versions, so all 5 existing tests in `DocsRequestBuilderTests.swift` must keep passing unmodified.

**Important — read before starting:** Google Docs' exact index behavior around a freshly inserted 1×1 table has NOT been verified against a live document by this project. This task uses two named constants with best-documented estimates (`tableCellContentOffset = 4`, `tableClosingOffset = 2`) isolated specifically so they're a one-line fix if wrong. Task 6 (manual QA) is where these get verified/corrected against a real Google Doc — don't treat the exact numeric values as certain during this task, just make sure they're isolated and easy to change.

- [ ] **Step 1: Write the failing test**

Add this test to the end of `SEOContentCreatorTests/DocsRequestBuilderTests.swift`, inside the existing `struct DocsRequestBuilderTests { ... }` (before the closing `}`):

```swift
    @Test func commercialSegmentBecomesTable() {
        let segments = [
            DocSegment(isCommercial: false, blocks: [
                DocBlock(style: .normal, listType: nil, text: "До", boldRanges: [])
            ]),
            DocSegment(isCommercial: true, blocks: [
                DocBlock(style: .normal, listType: nil, text: "Блок", boldRanges: [])
            ]),
            DocSegment(isCommercial: false, blocks: [
                DocBlock(style: .normal, listType: nil, text: "После", boldRanges: [])
            ])
        ]
        let reqs = DocsRequestBuilder.build(segments: segments)

        // "До" — plain paragraph starting at index 1.
        let firstInsert = reqs[0]["insertText"] as? [String: Any]
        #expect((firstInsert?["text"] as? String) == "До\n")
        #expect(((firstInsert?["location"] as? [String: Any])?["index"] as? Int) == 1)

        // Table inserted right after "До" ends (index 1 + len("До") + 1 = 4).
        let table = reqs[2]["insertTable"] as? [String: Any]
        #expect(((table?["location"] as? [String: Any])?["index"] as? Int) == 4)
        #expect(table?["rows"] as? Int == 1)
        #expect(table?["columns"] as? Int == 1)

        // Cell content starts at table index (4) + tableCellContentOffset (4) = 8.
        let cellInsert = reqs[3]["insertText"] as? [String: Any]
        #expect((cellInsert?["text"] as? String) == "Блок\n")
        #expect(((cellInsert?["location"] as? [String: Any])?["index"] as? Int) == 8)

        // "После" continues after the cell's content (8 + len("Блок") + 1 = 13)
        // plus tableClosingOffset (2) = 15.
        let lastInsert = reqs.last { ($0["insertText"] as? [String: Any])?["text"] as? String == "После\n" }
        let lastInsertBody = lastInsert?["insertText"] as? [String: Any]
        #expect(((lastInsertBody?["location"] as? [String: Any])?["index"] as? Int) == 15)
    }

    @Test func buildBlocksStillDelegatesToSingleNonCommercialSegment() {
        let blocks = [DocBlock(style: .heading1, listType: nil, text: "Заголовок", boldRanges: [])]
        let viaBlocks = DocsRequestBuilder.build(blocks: blocks)
        let viaSegments = DocsRequestBuilder.build(segments: [DocSegment(isCommercial: false, blocks: blocks)])
        #expect(viaBlocks.count == viaSegments.count)
        let a = viaBlocks.first?["insertText"] as? [String: Any]
        let b = viaSegments.first?["insertText"] as? [String: Any]
        #expect((a?["text"] as? String) == (b?["text"] as? String))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: FAIL to compile — `DocSegment` and `DocsRequestBuilder.build(segments:)` don't exist yet.

- [ ] **Step 3: Write the implementation**

Replace the whole contents of `SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift` with:

```swift
import Foundation

/// One paragraph-level content run for `DocsRequestBuilder`, tagged with
/// whether it should render as a bordered 1×1 table (a commercial block, see
/// `CommercialBlockSplitter`) or as ordinary body paragraphs.
struct DocSegment {
    let isCommercial: Bool
    let blocks: [DocBlock]
}

enum DocsRequestBuilder {
    /// Google Docs' documented behavior for a freshly inserted 1×1 table:
    /// the table, its single row, its single cell, and an auto-created empty
    /// paragraph are structural elements ahead of the cell's actual text
    /// insertion point. NOT yet verified against a live document by this
    /// project — isolated here as a single constant so a wrong guess is a
    /// one-line fix. See
    /// docs/superpowers/specs/2026-07-05-commercial-block-markers-design.md.
    static let tableCellContentOffset = 4

    /// Index positions between the end of the table cell's inserted content
    /// and the next body-level content that follows the table (closing the
    /// cell/row/table structural elements). Same "not yet live-verified"
    /// caveat as `tableCellContentOffset`.
    static let tableClosingOffset = 2

    /// Длина строки в UTF-16 (индексация Google Docs).
    private static func len(_ s: String) -> Int { s.utf16.count }

    static func build(blocks: [DocBlock]) -> [[String: Any]] {
        build(segments: [DocSegment(isCommercial: false, blocks: blocks)])
    }

    static func build(segments: [DocSegment]) -> [[String: Any]] {
        var requests: [[String: Any]] = []
        var cursor = 1
        for segment in segments {
            if segment.isCommercial {
                requests.append([
                    "insertTable": [
                        "location": ["index": cursor],
                        "rows": 1,
                        "columns": 1
                    ]
                ])
                let cellStart = cursor + tableCellContentOffset
                let (cellRequests, cellEnd) = blockRequests(segment.blocks, startingAt: cellStart)
                requests.append(contentsOf: cellRequests)
                cursor = cellEnd + tableClosingOffset
            } else {
                let (blockReqs, end) = blockRequests(segment.blocks, startingAt: cursor)
                requests.append(contentsOf: blockReqs)
                cursor = end
            }
        }
        return requests
    }

    /// Builds insertText + per-block style/list/bold requests for `blocks`,
    /// starting at document index `startIndex`. Returns the requests plus the
    /// index just past the last inserted block, so callers (top-level body or
    /// a table cell) can chain further content after it.
    private static func blockRequests(_ blocks: [DocBlock], startingAt startIndex: Int) -> (requests: [[String: Any]], endIndex: Int) {
        var fullText = ""
        for b in blocks { fullText += b.text + "\n" }

        var requests: [[String: Any]] = []
        if !fullText.isEmpty {
            requests.append([
                "insertText": [
                    "location": ["index": startIndex],
                    "text": fullText
                ]
            ])
        }

        var cursor = startIndex
        for b in blocks {
            let blockLen = len(b.text)
            let paraStart = cursor
            let paraEnd = cursor + blockLen + 1 // включая завершающий "\n"

            let named: String
            switch b.style {
            case .normal:   named = "NORMAL_TEXT"
            case .heading1: named = "HEADING_1"
            case .heading2: named = "HEADING_2"
            case .heading3: named = "HEADING_3"
            }
            requests.append([
                "updateParagraphStyle": [
                    "range": ["startIndex": paraStart, "endIndex": paraEnd],
                    "paragraphStyle": ["namedStyleType": named],
                    "fields": "namedStyleType"
                ]
            ])

            if let listType = b.listType {
                let preset = listType == .bullet ? "BULLET_DISC_CIRCLE_SQUARE" : "NUMBERED_DECIMAL_ALPHA_ROMAN"
                requests.append([
                    "createParagraphBullets": [
                        "range": ["startIndex": paraStart, "endIndex": paraEnd],
                        "bulletPreset": preset
                    ]
                ])
            }

            for r in b.boldRanges {
                let prefix = String(Array(b.text)[0..<r.lowerBound])
                let middle = String(Array(b.text)[r.lowerBound..<r.upperBound])
                let start = paraStart + len(prefix)
                let end = start + len(middle)
                requests.append([
                    "updateTextStyle": [
                        "range": ["startIndex": start, "endIndex": end],
                        "textStyle": ["bold": true],
                        "fields": "bold"
                    ]
                ])
            }

            cursor = paraEnd
        }
        return (requests, cursor)
    }

    static func buildReplacingBody(blocks: [DocBlock], existingBodyEndIndex: Int) -> [[String: Any]] {
        buildReplacingBody(segments: [DocSegment(isCommercial: false, blocks: blocks)], existingBodyEndIndex: existingBodyEndIndex)
    }

    static func buildReplacingBody(segments: [DocSegment], existingBodyEndIndex: Int) -> [[String: Any]] {
        var requests: [[String: Any]] = []
        if existingBodyEndIndex > 2 {
            requests.append([
                "deleteContentRange": [
                    "range": ["startIndex": 1, "endIndex": existingBodyEndIndex - 1]
                ]
            ])
        }
        requests.append(contentsOf: build(segments: segments))
        return requests
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`. Then via Cmd+U confirm all `DocsRequestBuilderTests` pass — the 5 pre-existing tests (`insertsAllTextFirst`, `setsHeadingParagraphStyle`, `computesBoldRangeInDocumentIndices`, `emitsBulletRequestForList`, `replacementRequestsDeleteExistingBodyBeforeInsert`) plus the 2 new ones added in this task.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift SEOContentCreator/SEOContentCreatorTests/DocsRequestBuilderTests.swift
git commit -m "Add DocSegment and table-building to DocsRequestBuilder"
```

---

## Task 3: Wire `ArticlePublisher` to split commercial blocks before publishing

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift:46-71`
- Modify: `SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift`

**Context:** `ArticlePublisher.publish` currently does `MarkdownDocParser.parse(...)` once on the whole normalized text, then `DocsRequestBuilder.build(blocks:)` / `buildReplacingBody(blocks:...)`. This task inserts `CommercialBlockSplitter.split` before parsing, parses each segment's text independently with the existing unmodified `MarkdownDocParser.parse`, wraps each into a `DocSegment`, and calls the new `build(segments:)` / `buildReplacingBody(segments:...)` from Task 2 instead.

- [ ] **Step 1: Write the failing test**

Add this test to the end of `SEOContentCreatorTests/ArticlePublisherTests.swift`, inside `struct ArticlePublisherTests { ... }` (before the closing `}`):

```swift
    @Test func publishWrapsCommercialBlockInTable() async throws {
        let context = try ctx()
        let topic = topicWithText(context, "Обычный текст.\n\n[[БЛОК]]\nКоммерческий текст.\n[[/БЛОК]]\n\nЕщё текст.")
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "f")

        await publisher.publish(topic: topic, mode: .newDocument, in: context)

        #expect(publisher.lastErrorMessage == nil)
        let requests = fake.batched.first?.1 ?? []
        let hasTable = requests.contains { $0["insertTable"] != nil }
        #expect(hasTable)
        let insertedTexts = requests.compactMap { ($0["insertText"] as? [String: Any])?["text"] as? String }
        #expect(insertedTexts.contains { $0.contains("Коммерческий текст.") })
        #expect(!insertedTexts.contains { $0.contains("[[БЛОК]]") })
        #expect(!insertedTexts.contains { $0.contains("[[/БЛОК]]") })
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: builds fine (it's only a test addition so far), but running it (Cmd+U) should FAIL: `hasTable` is false, and the raw `[[БЛОК]]`/`[[/БЛОК]]` markers are still present in the inserted text, because `ArticlePublisher` doesn't split on markers yet.

- [ ] **Step 3: Update `ArticlePublisher.publish`**

In `SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift`, replace:

```swift
            _ = try await tokenProvider()
            let blocks = MarkdownDocParser.parse(Self.normalizeHeading(text: version.text, h1: version.h1))
            let requests = DocsRequestBuilder.build(blocks: blocks)
```

with:

```swift
            _ = try await tokenProvider()
            let normalizedText = Self.normalizeHeading(text: version.text, h1: version.h1)
            let segments = CommercialBlockSplitter.split(normalizedText).map { segment in
                DocSegment(isCommercial: segment.isCommercial, blocks: MarkdownDocParser.parse(segment.text))
            }
            let requests = DocsRequestBuilder.build(segments: segments)
```

Then replace:

```swift
                docID = existing
                let endIndex = try await docs.documentBodyEndIndex(docID: docID)
                let replacementRequests = DocsRequestBuilder.buildReplacingBody(blocks: blocks, existingBodyEndIndex: endIndex)
```

with:

```swift
                docID = existing
                let endIndex = try await docs.documentBodyEndIndex(docID: docID)
                let replacementRequests = DocsRequestBuilder.buildReplacingBody(segments: segments, existingBodyEndIndex: endIndex)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`. Then via Cmd+U confirm `publishWrapsCommercialBlockInTable` passes, along with every pre-existing `ArticlePublisherTests` case (`newDocumentCreatesAndRecords`, `overwriteReusesExistingDocAndReplacesBody`, `noCurrentVersionSetsError`, `overwriteDoesNotRecordPublicationWhenReplacementFails`, `normalizeHeadingReplacesExistingH1`, `normalizeHeadingInsertsWhenMissing`, `normalizeHeadingKeepsTextWhenH1Nil`, `publishUsesNormalizedH1InRequestBody`) — none of them contain `[[БЛОК]]` markers, so `CommercialBlockSplitter.split` should return a single non-commercial segment for all of them and behavior should be unchanged.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift
git commit -m "ArticlePublisher: split commercial blocks before building Docs requests"
```

---

## Task 4: `MarkdownTextEditor` — Cmd+Shift+K shortcut + programmatic trigger

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/MarkdownTextEditor.swift`

**Context:** No automated tests for this file today (its keyboard-shortcut logic is untested AppKit glue, same convention as the rest of `MarkdownEditorTextView`) — verified by building and by the manual QA checklist in Task 6. `wrapSelection` already exists (used for Cmd+B/Cmd+I) but is `private`; this task makes it accessible to a new `wrapCommercialBlock()` method, and adds a request-counter property so `EditorSheet` can trigger the same wrap from a toolbar button (not just the keyboard shortcut).

- [ ] **Step 1: Replace the whole file**

```swift
import SwiftUI
import AppKit

/// A plain-text NSTextView wrapper for editing Markdown, with Google-Docs-style
/// keyboard shortcuts that insert/toggle Markdown syntax around the selection
/// or current line. The stored text stays a plain Markdown string — there is
/// no rich-text/AttributedString conversion. Background highlighting (see
/// `highlightRange`) uses `NSLayoutManager` temporary attributes, which are
/// display-only and never touch the stored string.
///
/// Shortcuts: Cmd+B bold (`**..**`), Cmd+I italic (`_.._`),
/// Cmd+Option+1/2/3 heading level 1/2/3 (`#`/`##`/`###` on the current line),
/// Cmd+Shift+K wraps the selection in `[[БЛОК]]`/`[[/БЛОК]]` markers (see
/// `CommercialBlockSplitter`). Cmd+1..3 are intentionally avoided — macOS
/// reserves them for window tab switching, which would swallow the key event
/// before the text view sees it.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 14)
    /// Set to `false` to make the editor temporarily read-only, e.g. while a
    /// fragment regeneration is in flight or awaiting accept/reject.
    var isEditable: Bool = true
    /// Called whenever the text view's selection changes. `range.length == 0`
    /// means an empty (caret-only) selection; `rect` is the selection's
    /// bounding box in the enclosing `NSScrollView`'s coordinate space (nil
    /// when the selection is empty), for positioning a SwiftUI overlay button.
    var onSelectionChange: (NSRange, CGRect?) -> Void = { _, _ in }
    /// When non-nil, this range gets a temporary highlighted background — used
    /// to mark a freshly regenerated fragment awaiting accept/reject.
    var highlightRange: NSRange?
    /// Bump this (e.g. `+= 1`) to programmatically wrap the current selection
    /// in `[[БЛОК]]`/`[[/БЛОК]]` markers from SwiftUI, without going through
    /// the Cmd+Shift+K keyboard shortcut — e.g. a toolbar button in
    /// `EditorSheet`. Any change in value triggers the wrap exactly once.
    var commercialBlockRequestID: Int = 0

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownEditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = font
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownEditorTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.font != font {
            textView.font = font
        }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        applyHighlight(to: textView)
        if commercialBlockRequestID != context.coordinator.lastCommercialBlockRequestID {
            context.coordinator.lastCommercialBlockRequestID = commercialBlockRequestID
            textView.wrapCommercialBlock()
        }
    }

    private func applyHighlight(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        guard let highlightRange,
              highlightRange.location >= 0,
              highlightRange.location + highlightRange.length <= fullRange.length
        else { return }
        layoutManager.addTemporaryAttribute(
            .backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.25),
            forCharacterRange: highlightRange
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSelectionChange: (NSRange, CGRect?) -> Void
        var lastCommercialBlockRequestID = 0

        init(text: Binding<String>, onSelectionChange: @escaping (NSRange, CGRect?) -> Void) {
            self.text = text
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            guard range.length > 0,
                  let layoutManager = tv.layoutManager,
                  let container = tv.textContainer,
                  let scrollView = tv.enclosingScrollView
            else {
                onSelectionChange(range, nil)
                return
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += tv.textContainerInset.width
            rect.origin.y += tv.textContainerInset.height
            let rectInScrollView = tv.convert(rect, to: scrollView)
            onSelectionChange(range, rectInScrollView)
        }
    }
}

/// Handles the Markdown keyboard shortcuts directly at the AppKit level, so
/// they work regardless of SwiftUI focus/selection-binding plumbing.
final class MarkdownEditorTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers {
            if event.modifierFlags.contains(.option) {
                switch chars {
                case "1": setHeading(level: 1); return
                case "2": setHeading(level: 2); return
                case "3": setHeading(level: 3); return
                default: break
                }
            } else if event.modifierFlags.contains(.shift) {
                switch chars {
                case "K", "k": wrapCommercialBlock(); return
                default: break
                }
            } else {
                switch chars {
                case "b": wrapSelection(prefix: "**", suffix: "**"); return
                case "i": wrapSelection(prefix: "_", suffix: "_"); return
                default: break
                }
            }
        }
        super.keyDown(with: event)
    }

    /// Wraps the current selection in `[[БЛОК]]`/`[[/БЛОК]]` marker lines,
    /// identifying a commercial block for `CommercialBlockSplitter` at
    /// publish time. Reachable via Cmd+Shift+K or programmatically via
    /// `MarkdownTextEditor.commercialBlockRequestID`.
    func wrapCommercialBlock() {
        wrapSelection(prefix: "[[БЛОК]]\n", suffix: "\n[[/БЛОК]]")
    }

    /// Wraps the current selection in `prefix`/`suffix`. With no selection,
    /// inserts an empty pair and places the cursor between them.
    private func wrapSelection(prefix: String, suffix: String) {
        let range = selectedRange()
        let ns = string as NSString
        let selected = ns.substring(with: range)
        let replacement = prefix + selected + suffix
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
        let cursor = selected.isEmpty
            ? range.location + (prefix as NSString).length
            : range.location + (replacement as NSString).length
        setSelectedRange(NSRange(location: cursor, length: 0))
    }

    /// Replaces the leading `#`s (if any) on the current line with `level` of them.
    private func setHeading(level: Int) {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        var line = ns.substring(with: lineRange)
        let hadTrailingNewline = line.hasSuffix("\n")
        if hadTrailingNewline { line.removeLast() }

        var body = Substring(line)
        while body.first == "#" { body = body.dropFirst() }
        if body.first == " " { body = body.dropFirst() }

        let newLine = String(repeating: "#", count: level) + " " + body + (hadTrailingNewline ? "\n" : "")
        guard shouldChangeText(in: lineRange, replacementString: newLine) else { return }
        replaceCharacters(in: lineRange, with: newLine)
        didChangeText()
        setSelectedRange(NSRange(location: lineRange.location + (newLine as NSString).length, length: 0))
    }
}
```

Note: `updateNSView`'s guard changed from `as? NSTextView` to `as? MarkdownEditorTextView` (needed to call `wrapCommercialBlock()`, which is declared on the subclass) — this is a strictly narrower cast of the same concrete type `makeNSView` already creates, so it will never fail in practice.

- [ ] **Step 2: Verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: `** TEST BUILD SUCCEEDED **` (this file's only current caller, `EditorSheet.swift`, doesn't pass `commercialBlockRequestID` yet, but it has a default value of `0`, so nothing breaks until Task 5 wires it up).

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/MarkdownTextEditor.swift
git commit -m "MarkdownTextEditor: Cmd+Shift+K and programmatic trigger for [[БЛОК]] markers"
```

---

## Task 5: Wire a toolbar button into `EditorSheet`

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/EditorSheet.swift`

- [ ] **Step 1: Add state and pass it to `MarkdownTextEditor`**

In `EditorSheet`, add a new `@State` property alongside the existing ones (after `@State private var editor = FragmentEditor.live()`):

```swift
    @State private var commercialBlockRequestID = 0
```

Then in `editorArea`, update the `MarkdownTextEditor(...)` call to pass it:

```swift
            MarkdownTextEditor(
                text: $text,
                font: .systemFont(ofSize: 15),
                isEditable: sessionState.isTextEditable,
                onSelectionChange: { range, rect in
                    selectedRange = range
                    selectionRect = rect
                },
                highlightRange: highlightRange,
                commercialBlockRequestID: commercialBlockRequestID
            )
```

- [ ] **Step 2: Add the toolbar button**

In the bottom `HStack` (Отмена / Перегенерировать выделенное / Сохранить), add a new button between "Перегенерировать выделенное" and "Сохранить":

```swift
            HStack {
                Button("Отмена") { dismiss() }
                    .disabled(!canCloseSheet)
                Spacer()
                Button("Перегенерировать выделенное") { showRegenerateCard = true }
                    .disabled(!canTriggerRegenerate)
                Button("Отметить как коммерческий блок") { commercialBlockRequestID += 1 }
                    .disabled(!canTriggerRegenerate)
                Button("Сохранить", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
```

(Reuses `canTriggerRegenerate` — a non-empty selection while idle — as the enabling condition, since marking a commercial block only makes sense on a real selection and while the editor isn't mid-generation/review, exactly the same precondition as regenerating a fragment.)

- [ ] **Step 3: Update the caption text**

Replace:

```swift
            Text("Правка сохранится как новая версия и станет текущей, когда нажмёте «Сохранить». Выделите фрагмент и нажмите «Переписать», чтобы перегенерировать его через ИИ. Cmd+B — жирный, Cmd+I — курсив, Cmd+Option+1/2/3 — заголовок.")
                .font(.caption).foregroundStyle(.secondary)
```

with:

```swift
            Text("Правка сохранится как новая версия и станет текущей, когда нажмёте «Сохранить». Выделите фрагмент и нажмите «Переписать», чтобы перегенерировать его через ИИ. Cmd+B — жирный, Cmd+I — курсив, Cmd+Option+1/2/3 — заголовок, Cmd+Shift+K — коммерческий блок (в рамке при публикации в Google Docs).")
                .font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 4: Verify it compiles**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -iE "error:|BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/EditorSheet.swift
git commit -m "EditorSheet: add toolbar button to mark a commercial block"
```

---

## Task 6: Manual QA — including mandatory live Google Docs verification

**Files:** none (manual verification only).

- [ ] **Step 1: Build and reinstall for manual testing**

```bash
cd SEOContentCreator && xcodebuild build -scheme SEOContentCreator -configuration Release
```
Quit any running copy, replace `/Applications/SEOContentCreator.app` with the fresh build, relaunch.

- [ ] **Step 2: In-app checks**

1. Open a topic with an accepted version, open "Редактор".
2. Select a paragraph, press Cmd+Shift+K — confirm `[[БЛОК]]`/`[[/БЛОК]]` appear around it on their own lines.
3. Select a different paragraph, click the new "Отметить как коммерческий блок" toolbar button — confirm it does the same thing.
4. Confirm the button and the shortcut are disabled/no-ops when nothing is selected.
5. Save, reopen the editor — confirm the markers persisted as plain text in the saved version.

- [ ] **Step 3: Live Google Docs verification (mandatory — do not skip)**

1. Publish this article as a **new document** (needs a configured Google account per `ai/external-tools.md`).
2. Open the resulting Google Doc and confirm:
   - The commercial block appears as a 1×1 table with a visible thin black border, containing exactly the marked text (no `[[БЛОК]]`/`[[/БЛОК]]` visible anywhere).
   - Text before and after the table is intact, correctly ordered, and not missing/duplicating any characters at the boundary.
   - If the article had bold text or a list inside the commercial block, confirm that formatting rendered correctly inside the table cell.
3. Publish the same topic again in **overwrite** mode and confirm the same result (this exercises `buildReplacingBody(segments:...)`).
4. **If the table or surrounding text is misplaced, missing characters, or has extra blank paragraphs:** this means `DocsRequestBuilder.tableCellContentOffset` and/or `tableClosingOffset` (in `SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift`) need correcting. Adjust the constant(s), rebuild, and repeat this step until a live-published document looks correct. Record the corrected values (and what evidence led to them) in `ai/changelog.md` during `task-finish`, since the design doc's stated values were estimates pending exactly this check.
5. Test an article with two commercial blocks and normal text in between, before, and after, to confirm the running cursor logic handles multiple tables correctly end to end.

- [ ] **Step 4: Report**

Record the outcome (including any offset corrections made in Step 3.4) in `ai/changelog.md` as part of `task-finish` — not before, and not as part of this plan's execution.
