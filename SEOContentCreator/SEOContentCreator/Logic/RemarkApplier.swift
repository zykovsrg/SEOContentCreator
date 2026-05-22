import Foundation

enum RemarkApplier {
    /// Applies accepted remarks to `base` by replacing the first remaining occurrence of each
    /// non-empty `quote` with its `suggestion`, in the given order. Quotes not found are skipped.
    static func apply(base: String, accepted: [Remark]) -> String {
        var result = base
        for remark in accepted where !remark.quote.isEmpty {
            if let range = result.range(of: remark.quote) {
                result.replaceSubrange(range, with: remark.suggestion)
            }
        }
        return result
    }
}
