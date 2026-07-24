import Foundation

enum RemarkApplier {
    /// SEO remarks about Title/H1/Description target fields that live outside the
    /// article body (`ArticleVersion.h1/seoTitle/seoDescription`) — the prompt shows
    /// the model these as separate context lines ("H1: …", "Title: …", "Description: …"),
    /// never as part of `{{текущий_текст}}`, so their `quote` is never findable in the
    /// body and must not be searched for there.
    enum MetadataField: String, CaseIterable {
        case h1, seoTitle, seoDescription
    }

    /// Outcome of applying accepted remarks.
    struct ApplyResult: Equatable {
        /// Article body text: matched replacements applied in place, plus a trailing
        /// block for any remark whose quote could not be located (see `appendedIDs`).
        var text: String
        /// Remarks recognised as Title/H1/Description edits: applied directly to those
        /// fields (never searched for in the body), keyed by target field.
        var metadataEdits: [MetadataField: String] = [:]
        /// Accepted remarks whose quote was not found in the body, so — per the user's
        /// request that a correction must never be silently dropped — their suggestion
        /// was appended in a clearly marked trailing block instead of being lost.
        var appendedIDs: Set<UUID> = []
        /// Accepted remarks that produced nothing at all: the quote normalises to
        /// nothing referenceable (e.g. stray Markdown punctuation) and there is no
        /// suggestion text worth appending on its own.
        var unresolvedIDs: Set<UUID> = []
    }

    /// A run of text, tagged once it came from an applied `suggestion` so later
    /// remarks cannot match inside text a previous remark just inserted.
    private struct Segment {
        var text: String
        var protected: Bool
    }

    /// Applies accepted remarks to `base`.
    ///
    /// Title/H1/Description remarks (see `MetadataField`) are routed to `metadataEdits`
    /// and never searched for in the body — there is nothing to find, since those fields
    /// aren't part of the article text in the first place.
    ///
    /// Remaining remarks replace the first remaining, unprotected match of their `quote`
    /// in the body, in the given order. Matching is tolerant: the model rarely echoes the
    /// article byte-for-byte, so quotes are compared on a normalised projection (collapsed
    /// whitespace, dropped Markdown emphasis, unified quotes/dashes, ё→е, case-folded)
    /// while the replacement still lands on the exact original range — a false replacement
    /// is worse than a reported miss, so matching never guesses.
    ///
    /// A quote with no match is never just dropped: its suggestion is appended in a
    /// trailing "не удалось разместить автоматически" block (`appendedIDs`), so every
    /// accepted correction ends up somewhere in the text. Only a degenerate quote with
    /// nothing to reference and no suggestion to fall back on is truly unresolved.
    static func apply(base: String, accepted: [Remark]) -> ApplyResult {
        var segments = [Segment(text: base, protected: false)]
        var unresolved = Set<UUID>()
        var appended = Set<UUID>()
        var trailing: [(quote: String, suggestion: String)] = []
        var metadataEdits: [MetadataField: String] = [:]

        for remark in accepted {
            if let (field, value) = metadataField(for: remark) {
                metadataEdits[field] = value
                continue
            }
            guard !remark.quote.isEmpty else { continue }
            let needle = trimSpaces(project(remark.quote).chars)
            guard !needle.isEmpty else {
                unresolved.insert(remark.id)   // nothing referenceable in the quote at all
                continue
            }
            guard let (index, range) = firstUnprotectedMatch(needle: needle, in: segments) else {
                if remark.suggestion.isEmpty {
                    unresolved.insert(remark.id)   // nothing to add: was a removal that isn't there
                } else {
                    appended.insert(remark.id)
                    trailing.append((remark.quote, remark.suggestion))
                }
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

        var text = segments.map(\.text).joined()
        if !trailing.isEmpty {
            let block = trailing.map { "- «\($0.quote)» → \($0.suggestion.isEmpty ? "(удалить)" : $0.suggestion)" }
                .joined(separator: "\n")
            text += "\n\n## Правки, которые не удалось разместить автоматически\n" + block
        }
        return ApplyResult(text: text, metadataEdits: metadataEdits, appendedIDs: appended, unresolvedIDs: unresolved)
    }

    /// Recognises a Title/H1/Description remark from its `quote` prefix — the exact
    /// labels `StageTemplateDefaults.seoCheck`'s prompt shows the model as context
    /// ("H1: …", "Title: …", "Description: …") — and extracts the new value from
    /// `suggestion`, stripping the same label prefix if the model echoed it back too
    /// (as in "станет: Title: Новый заголовок").
    private static func metadataField(for remark: Remark) -> (MetadataField, String)? {
        let prefixes: [(String, MetadataField)] = [
            ("h1:", .h1), ("title:", .seoTitle), ("description:", .seoDescription)
        ]
        let loweredQuote = remark.quote.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let (prefix, field) = prefixes.first(where: { loweredQuote.hasPrefix($0.0) }) else { return nil }
        var value = remark.suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (field, value)
    }

    private static func firstUnprotectedMatch(
        needle: [Character], in segments: [Segment]
    ) -> (index: Int, range: Range<String.Index>)? {
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
