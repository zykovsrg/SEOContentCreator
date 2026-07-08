import Foundation

struct PromptVariableInsertionResult: Equatable {
    let text: String
    let selectedRange: NSRange
}

enum PromptVariableInsertion {
    static func insert(_ token: String, into text: String, selectedRange: NSRange) -> PromptVariableInsertionResult {
        let ns = text as NSString
        let start = max(0, min(selectedRange.location, ns.length))
        let maxLength = ns.length - start
        let length = max(0, min(selectedRange.length, maxLength))
        let clamped = NSRange(location: start, length: length)
        let next = ns.replacingCharacters(in: clamped, with: token)
        return PromptVariableInsertionResult(
            text: next,
            selectedRange: NSRange(location: start + (token as NSString).length, length: 0)
        )
    }
}
