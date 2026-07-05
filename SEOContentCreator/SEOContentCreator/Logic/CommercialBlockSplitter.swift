import Foundation

/// One contiguous run of the article's Markdown text, tagged with whether it
/// falls inside a `[[БЛОК]]`...`[[/БЛОК]]` pair. Produced by
/// `CommercialBlockSplitter.split` for the publish pipeline to turn into a
/// bordered table (see `DocsRequestBuilder`).
struct TextSegment: Equatable {
    let isCommercial: Bool
    let text: String
}

/// Splits an article's raw Markdown text into ordered commercial/non-
/// commercial segments, using `[[БЛОК]]`/`[[/БЛОК]]` marker lines the user
/// inserts manually in the editor (see `MarkdownTextEditor`'s Cmd+Shift+K).
/// Markers are stripped from the returned segment text.
enum CommercialBlockSplitter {
    private static let openMarker = "[[БЛОК]]"
    private static let closeMarker = "[[/БЛОК]]"

    /// An unmatched `[[БЛОК]]` (no closing marker before the next opener or
    /// the end of the text) is never treated as an error: everything from
    /// that point on is kept as literal plain text, so a typo or stray
    /// bracket can never silently drop article content.
    static func split(_ markdown: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var plainBuffer = ""
        var remainder = Substring(markdown)

        while !remainder.isEmpty {
            guard let openRange = remainder.range(of: openMarker) else {
                plainBuffer += remainder
                remainder = ""
                break
            }
            guard let closeRange = remainder.range(of: closeMarker, range: openRange.upperBound..<remainder.endIndex) else {
                plainBuffer += remainder
                remainder = ""
                break
            }

            plainBuffer += remainder[remainder.startIndex..<openRange.lowerBound]
            appendPlainSegmentIfNeeded(&segments, &plainBuffer)

            let inner = remainder[openRange.upperBound..<closeRange.lowerBound]
            segments.append(TextSegment(isCommercial: true, text: trimNewlines(String(inner))))

            remainder = remainder[closeRange.upperBound...]
        }
        appendPlainSegmentIfNeeded(&segments, &plainBuffer)

        return segments
    }

    private static func appendPlainSegmentIfNeeded(_ segments: inout [TextSegment], _ plainBuffer: inout String) {
        let trimmed = trimNewlines(plainBuffer)
        if !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(TextSegment(isCommercial: false, text: trimmed))
        }
        plainBuffer = ""
    }

    private static func trimNewlines(_ s: String) -> String {
        var result = Substring(s)
        while result.first == "\n" { result = result.dropFirst() }
        while result.last == "\n" { result = result.dropLast() }
        return String(result)
    }
}
