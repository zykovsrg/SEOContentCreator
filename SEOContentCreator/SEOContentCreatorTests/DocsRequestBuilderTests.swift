import Testing
@testable import SEOContentCreator

struct DocsRequestBuilderTests {
    @Test func insertsAllTextFirst() {
        let blocks = [DocBlock(style: .heading1, listType: nil, text: "Заголовок", boldRanges: [])]
        let reqs = DocsRequestBuilder.build(blocks: blocks)
        let insert = reqs.first?["insertText"] as? [String: Any]
        #expect((insert?["text"] as? String) == "Заголовок\n")
        let loc = insert?["location"] as? [String: Any]
        #expect((loc?["index"] as? Int) == 1)
    }

    @Test func setsHeadingParagraphStyle() {
        let blocks = [DocBlock(style: .heading2, listType: nil, text: "Подзаголовок", boldRanges: [])]
        let reqs = DocsRequestBuilder.build(blocks: blocks)
        let styled = reqs.compactMap { $0["updateParagraphStyle"] as? [String: Any] }
        let named = (styled.first?["paragraphStyle"] as? [String: Any])?["namedStyleType"] as? String
        #expect(named == "HEADING_2")
    }

    @Test func computesBoldRangeInDocumentIndices() {
        let blocks = [DocBlock(style: .normal, listType: nil, text: "AB C", boldRanges: [3..<4])]
        let reqs = DocsRequestBuilder.build(blocks: blocks)
        let textStyle = reqs.compactMap { $0["updateTextStyle"] as? [String: Any] }.first
        let range = textStyle?["range"] as? [String: Any]
        // текст вставлен с индекса 1 → "C" на позиции 1+3=4..<1+4=5
        #expect((range?["startIndex"] as? Int) == 4)
        #expect((range?["endIndex"] as? Int) == 5)
        #expect(((textStyle?["textStyle"] as? [String: Any])?["bold"] as? Bool) == true)
    }

    @Test func emitsBulletRequestForList() {
        let blocks = [
            DocBlock(style: .normal, listType: .bullet, text: "пункт", boldRanges: [])
        ]
        let reqs = DocsRequestBuilder.build(blocks: blocks)
        let bullets = reqs.compactMap { $0["createParagraphBullets"] as? [String: Any] }
        #expect(bullets.count == 1)
    }

    @Test func replacementRequestsDeleteExistingBodyBeforeInsert() {
        let blocks = [DocBlock(style: .normal, listType: nil, text: "Новый текст", boldRanges: [])]
        let reqs = DocsRequestBuilder.buildReplacingBody(blocks: blocks, existingBodyEndIndex: 20)
        let delete = reqs.first?["deleteContentRange"] as? [String: Any]
        let range = delete?["range"] as? [String: Any]
        #expect(range?["startIndex"] as? Int == 1)
        #expect(range?["endIndex"] as? Int == 19)

        let insert = reqs.dropFirst().first?["insertText"] as? [String: Any]
        #expect((insert?["text"] as? String) == "Новый текст\n")
    }

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
}
