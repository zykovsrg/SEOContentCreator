import Testing
import Foundation
@testable import SEOContentCreator

struct ImageResponseParserTests {
    @Test func decodesB64FromDataArray() throws {
        let bytes = Data([1, 2, 3, 4])
        let b64 = bytes.base64EncodedString()
        let json = "{\"data\":[{\"b64_json\":\"\(b64)\"}]}"
        let result = try ImageResponseParser.parse(Data(json.utf8))
        #expect(result == bytes)
    }

    @Test func brokenJSONThrowsBadResponse() {
        #expect(throws: OpenAIClient.OpenAIError.badResponse) {
            _ = try ImageResponseParser.parse(Data("{\"oops\":true}".utf8))
        }
    }
}
