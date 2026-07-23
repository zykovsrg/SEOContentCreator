import Testing
import Foundation
@testable import SEOContentCreator

struct WordstatResponseParserTests {
    private func fixture() throws -> Data {
        let url = Bundle(for: BundleMarker.self)
            .url(forResource: "wordstat-cloud-sample", withExtension: "json")
        let path = try #require(url)
        return try Data(contentsOf: path)
    }

    @Test func parsesPhrasesWithFrequencies() throws {
        let phrases = try WordstatResponseParser.parse(fixture())

        #expect(phrases.count == 5)
        #expect(phrases[0] == WordstatPhrase(text: "рак молочной железы лечение", frequency: 15927))
    }

    @Test func decodesCountEncodedAsString() throws {
        // The Cloud API sends count as a string (gRPC int64 serialization).
        let data = Data("""
        {"totalCount":"1","results":[{"phrase":"пример","count":"42"}],"associations":[]}
        """.utf8)

        let phrases = try WordstatResponseParser.parse(data)

        #expect(phrases == [WordstatPhrase(text: "пример", frequency: 42)])
    }

    @Test func skipsBlankPhrases() throws {
        let data = Data("""
        {"totalCount":"1","results":[{"phrase":"  ","count":"5"}],"associations":[]}
        """.utf8)

        let phrases = try WordstatResponseParser.parse(data)

        #expect(phrases.isEmpty)
    }

    @Test func treatsEmptyObjectAsNoPhrases() throws {
        // Confirmed live against the real Cloud API: when Wordstat has no
        // data at all for a phrase, it returns HTTP 200 with body `{}` —
        // the "results" field is omitted entirely, not sent as `[]`. This
        // must not be treated as a parse failure.
        let data = Data("{}".utf8)

        let phrases = try WordstatResponseParser.parse(data)

        #expect(phrases.isEmpty)
    }

    @Test func throwsOnMalformedJSON() {
        let data = Data("не json".utf8)

        #expect(throws: WordstatResponseParser.ParserError.badResponse) {
            try WordstatResponseParser.parse(data)
        }
    }
}

/// Anchors `Bundle(for:)` to the test bundle so the fixture resolves.
private final class BundleMarker {}
