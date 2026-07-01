import Foundation

enum DocsRequestBuilder {
    /// Длина строки в UTF-16 (индексация Google Docs).
    private static func len(_ s: String) -> Int { s.utf16.count }

    static func build(blocks: [DocBlock]) -> [[String: Any]] {
        var fullText = ""
        for b in blocks { fullText += b.text + "\n" }

        var requests: [[String: Any]] = []
        if !fullText.isEmpty {
            requests.append([
                "insertText": [
                    "location": ["index": 1],
                    "text": fullText
                ]
            ])
        }

        var cursor = 1
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
        return requests
    }

    static func buildReplacingBody(blocks: [DocBlock], existingBodyEndIndex: Int) -> [[String: Any]] {
        var requests: [[String: Any]] = []
        if existingBodyEndIndex > 2 {
            requests.append([
                "deleteContentRange": [
                    "range": ["startIndex": 1, "endIndex": existingBodyEndIndex - 1]
                ]
            ])
        }
        requests.append(contentsOf: build(blocks: blocks))
        return requests
    }
}
