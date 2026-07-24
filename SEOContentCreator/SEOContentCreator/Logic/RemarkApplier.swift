import Foundation

enum RemarkApplier {
    /// Outcome of applying accepted remarks: the resulting text plus the ids of
    /// accepted remarks whose `quote` could not be located (so the UI can flag
    /// them as "не применено" instead of dropping them silently).
    struct ApplyResult: Equatable {
        var text: String
        var unresolvedIDs: Set<UUID>
    }

    /// A run of text, tagged once it came from an applied `suggestion` so later
    /// remarks cannot match inside text a previous remark just inserted.
    private struct Segment {
        var text: String
        var protected: Bool
    }

    /// Applies accepted remarks to `base` by replacing the first remaining, unprotected
    /// match of each non-empty `quote` with its `suggestion`, in the given order.
    ///
    /// Matching is tolerant: the model rarely echoes the article byte-for-byte, so
    /// quotes are compared on a normalised projection (collapsed whitespace, dropped
    /// Markdown emphasis, unified quotes/dashes, ё→е, case-folded) while the replacement
    /// still lands on the exact original range. A quote that has no match (or normalises
    /// to nothing) is reported in `unresolvedIDs`, never applied at the wrong place —
    /// a false replacement is worse than a reported miss. Empty quotes are advisory and
    /// are neither applied nor reported.
    static func apply(base: String, accepted: [Remark]) -> ApplyResult {
        var segments = [Segment(text: base, protected: false)]
        var unresolved = Set<UUID>()
        for remark in accepted {
            guard !remark.quote.isEmpty else { continue }
            guard let (index, range) = firstUnprotectedMatch(of: remark.quote, in: segments) else {
                unresolved.insert(remark.id)
                continue
            }
            let segment = segments[index]
            let before = String(segment.text[segment.text.startIndex..<range.lowerBound])
            let after = String(segment.text[range.upperBound...])
            var replacement: [Segment] = []
            if !before.isEmpty { replacement.append(Segment(text: before, protected: false)) }
            replacement.append(Segment(text: remark.suggestion, protected: true))
            if !after.isEmpty { replacement.append(Segment(text: after, protected: false)) }
            segments.replaceSubrange(index...index, with: replacement)
        }
        return ApplyResult(text: segments.map(\.text).joined(), unresolvedIDs: unresolved)
    }

    private static func firstUnprotectedMatch(
        of quote: String, in segments: [Segment]
    ) -> (index: Int, range: Range<String.Index>)? {
        let needle = trimSpaces(project(quote).chars)
        guard !needle.isEmpty else { return nil }
        for (index, segment) in segments.enumerated() where !segment.protected {
            if let range = search(needle, in: project(segment.text)) {
                return (index, range)
            }
        }
        return nil
    }

    // MARK: - Normalised projection

    /// A normalised view of a string for fuzzy matching, keeping, for each normalised
    /// character, the original index range it came from so a match maps back exactly.
    private struct Projection {
        var chars: [Character]
        var starts: [String.Index]
        var ends: [String.Index]
    }

    private static func project(_ s: String) -> Projection {
        var chars: [Character] = []
        var starts: [String.Index] = []
        var ends: [String.Index] = []

        var pendingWS = false
        var wsStart = s.startIndex
        var wsEnd = s.startIndex
        func flushWS() {
            guard pendingWS else { return }
            chars.append(" "); starts.append(wsStart); ends.append(wsEnd)
            pendingWS = false
        }

        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            let next = s.index(after: i)
            if ch.isWhitespace {
                if !pendingWS { pendingWS = true; wsStart = i }
                wsEnd = next
                i = next
                continue
            }
            flushWS()
            for normalized in normalizedForms(ch) {
                chars.append(normalized); starts.append(i); ends.append(next)
            }
            i = next
        }
        flushWS()
        return Projection(chars: chars, starts: starts, ends: ends)
    }

    /// Normalised character(s) for matching, or `[]` to drop the character entirely.
    private static func normalizedForms(_ ch: Character) -> [Character] {
        switch ch {
        case "*", "`", "_", "#", "~": return []                 // Markdown emphasis / heading marks
        case "«", "»", "“", "”", "„", "\"": return ["\""]
        case "‘", "’", "‚": return ["'"]
        case "—", "–", "−", "‐", "‑", "-": return ["-"]
        case "…": return [".", ".", "."]
        case "ё", "Ё": return ["е"]
        default:
            let lowered = ch.lowercased()
            return lowered.isEmpty ? [ch] : Array(lowered)
        }
    }

    private static func trimSpaces(_ chars: [Character]) -> [Character] {
        var start = 0
        var end = chars.count
        while start < end, chars[start] == " " { start += 1 }
        while end > start, chars[end - 1] == " " { end -= 1 }
        return Array(chars[start..<end])
    }

    /// First occurrence of `needle` (normalised chars) inside `haystack`, mapped
    /// back to a range in the haystack's original string.
    private static func search(
        _ needle: [Character], in haystack: Projection
    ) -> Range<String.Index>? {
        let hay = haystack.chars
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        let last = hay.count - needle.count
        var i = 0
        while i <= last {
            var j = 0
            while j < needle.count, hay[i + j] == needle[j] { j += 1 }
            if j == needle.count {
                return haystack.starts[i]..<haystack.ends[i + needle.count - 1]
            }
            i += 1
        }
        return nil
    }
}
