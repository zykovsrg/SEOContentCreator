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
}
