import Foundation

/// Splits text into paragraph ranges (on blank-line "\n\n" boundaries). Used to
/// give per-paragraph `.id()`s to scrollable highlighted-text views so a
/// `ScrollViewReader` can center on the paragraph containing a given range.
enum TextParagraphs {
    static func ranges(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        var searchStart = text.startIndex
        while let sepRange = text.range(of: "\n\n", range: searchStart..<text.endIndex) {
            result.append(start..<sepRange.lowerBound)
            start = sepRange.upperBound
            searchStart = sepRange.upperBound
        }
        result.append(start..<text.endIndex)
        return result
    }

    /// Index of the paragraph range containing `position` in `ranges`.
    static func index(of position: String.Index, in ranges: [Range<String.Index>]) -> Int? {
        ranges.firstIndex { $0.contains(position) || $0.upperBound == position }
    }
}
