import SwiftUI

/// Plain text that highlights the first occurrence of `highlight` (if any).
/// Rendered paragraph-by-paragraph, each tagged with `.id(index)` from
/// `TextParagraphs`, so a `ScrollViewReader` can scroll to and center the
/// paragraph containing the highlight.
struct HighlightedText: View {
    var text: String
    var highlight: String?

    private var paragraphs: [Range<String.Index>] { TextParagraphs.ranges(in: text) }

    private var highlightRange: Range<String.Index>? {
        guard let highlight, !highlight.isEmpty else { return nil }
        return text.range(of: highlight)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, range in
                Text(attributed(for: range))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
            }
        }
        .textSelection(.enabled)
    }

    private func attributed(for paragraphRange: Range<String.Index>) -> AttributedString {
        var a = AttributedString(String(text[paragraphRange]))
        guard let highlightRange else { return a }
        let lower = max(highlightRange.lowerBound, paragraphRange.lowerBound)
        let upper = min(highlightRange.upperBound, paragraphRange.upperBound)
        guard lower < upper else { return a }
        let lowerOffset = text.distance(from: paragraphRange.lowerBound, to: lower)
        let upperOffset = text.distance(from: paragraphRange.lowerBound, to: upper)
        guard lowerOffset >= 0, upperOffset <= a.characters.count, lowerOffset < upperOffset else { return a }
        let aLower = a.index(a.startIndex, offsetByCharacters: lowerOffset)
        let aUpper = a.index(a.startIndex, offsetByCharacters: upperOffset)
        a[aLower..<aUpper].backgroundColor = .yellow.opacity(0.45)
        return a
    }
}
