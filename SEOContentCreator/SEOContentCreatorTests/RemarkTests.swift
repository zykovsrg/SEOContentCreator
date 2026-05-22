import Testing
@testable import SEOContentCreator

struct RemarkTests {
    @Test func parsesRemarksFromFencedJSON() {
        let raw = """
        Вот замечания:
        ```json
        {"remarks":[{"category":"Канцелярит","quote":"осуществляется","suggestion":"делается","explanation":"проще"}]}
        ```
        """
        let remarks = RemarksParser.parse(rawText: raw)
        #expect(remarks.count == 1)
        #expect(remarks.first?.category == "Канцелярит")
        #expect(remarks.first?.quote == "осуществляется")
        #expect(remarks.first?.suggestion == "делается")
        #expect(remarks.first?.explanation == "проще")
    }

    @Test func parsesRawJSONObject() {
        let raw = #"{"remarks":[{"category":"Факт","quote":"5000","suggestion":"4500","explanation":"в справочнике 4500"}]}"#
        let remarks = RemarksParser.parse(rawText: raw)
        #expect(remarks.count == 1)
        #expect(remarks.first?.suggestion == "4500")
    }

    @Test func brokenOrEmptyReturnsEmpty() {
        #expect(RemarksParser.parse(rawText: "нет json").isEmpty)
        #expect(RemarksParser.parse(rawText: "").isEmpty)
        #expect(RemarksParser.parse(rawText: #"{"remarks": "не массив"}"#).isEmpty)
    }

    @Test func eachRemarkGetsUniqueID() {
        let raw = #"{"remarks":[{"category":"A","quote":"x","suggestion":"y","explanation":"e"},{"category":"B","quote":"z","suggestion":"w","explanation":"e2"}]}"#
        let remarks = RemarksParser.parse(rawText: raw)
        #expect(remarks.count == 2)
        #expect(remarks[0].id != remarks[1].id)
    }
}
