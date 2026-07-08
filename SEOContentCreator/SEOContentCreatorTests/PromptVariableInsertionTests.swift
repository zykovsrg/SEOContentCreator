import Foundation
import Testing
@testable import SEOContentCreator

struct PromptVariableInsertionTests {
    @Test func insertsTokenAtCursor() {
        let result = PromptVariableInsertion.insert("{{тема}}", into: "Тема: ", selectedRange: NSRange(location: 6, length: 0))
        #expect(result.text == "Тема: {{тема}}")
        #expect(result.selectedRange.location == 14)
        #expect(result.selectedRange.length == 0)
    }

    @Test func replacesSelectedText() {
        let result = PromptVariableInsertion.insert("{{тип}}", into: "Тип: старый", selectedRange: NSRange(location: 5, length: 6))
        #expect(result.text == "Тип: {{тип}}")
        #expect(result.selectedRange.location == 12)
        #expect(result.selectedRange.length == 0)
    }

    @Test func clampsOutOfBoundsRangeToEnd() {
        let result = PromptVariableInsertion.insert("{{объём}}", into: "Объём: ", selectedRange: NSRange(location: 100, length: 20))
        #expect(result.text == "Объём: {{объём}}")
    }
}
