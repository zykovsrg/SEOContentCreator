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
