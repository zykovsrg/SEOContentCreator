import Foundation

enum FragmentSplicer {
    enum Result: Equatable {
        case replaced(String)
        case notFound
        case ambiguous(Int)
    }

    /// Replaces the fragment in the full text only when it occurs exactly once.
    static func splice(fullText: String, fragment: String, replacement: String) -> Result {
        guard !fragment.isEmpty else { return .notFound }
        let count = occurrences(of: fragment, in: fullText)
        switch count {
        case 0:
            return .notFound
        case 1:
            return .replaced(fullText.replacingOccurrences(of: fragment, with: replacement))
        default:
            return .ambiguous(count)
        }
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var range = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: range) {
            count += 1
            range = found.upperBound..<haystack.endIndex
        }
        return count
    }
}
