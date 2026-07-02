import Foundation

enum RemarkApplier {
    /// A run of text, tagged once it came from an applied `suggestion` so later
    /// remarks cannot match inside text a previous remark just inserted.
    private struct Segment {
        var text: String
        var protected: Bool
    }

    /// Applies accepted remarks to `base` by replacing the first remaining, unprotected
    /// occurrence of each non-empty `quote` with its `suggestion`, in the given order.
    /// Quotes not found (or found only inside a previously-applied suggestion) are skipped.
    static func apply(base: String, accepted: [Remark]) -> String {
        var segments = [Segment(text: base, protected: false)]
        for remark in accepted where !remark.quote.isEmpty {
            guard let (index, range) = firstUnprotectedMatch(of: remark.quote, in: segments) else { continue }
            let segment = segments[index]
            let before = String(segment.text[segment.text.startIndex..<range.lowerBound])
            let after = String(segment.text[range.upperBound...])
            var replacement: [Segment] = []
            if !before.isEmpty { replacement.append(Segment(text: before, protected: false)) }
            replacement.append(Segment(text: remark.suggestion, protected: true))
            if !after.isEmpty { replacement.append(Segment(text: after, protected: false)) }
            segments.replaceSubrange(index...index, with: replacement)
        }
        return segments.map(\.text).joined()
    }

    private static func firstUnprotectedMatch(
        of quote: String, in segments: [Segment]
    ) -> (index: Int, range: Range<String.Index>)? {
        for (index, segment) in segments.enumerated() where !segment.protected {
            if let range = segment.text.range(of: quote) {
                return (index, range)
            }
        }
        return nil
    }
}
