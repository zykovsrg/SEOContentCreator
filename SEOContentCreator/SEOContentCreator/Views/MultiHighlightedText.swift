import SwiftUI

/// Read-only text that paints several colored background ranges, with one
/// optional emphasized range drawn stronger. Ranges are `String.Index` ranges
/// into the SAME `text` value passed in. Rendered paragraph-by-paragraph, each
/// tagged with `.id(index)` from `TextParagraphs`, so a `ScrollViewReader` can
/// scroll to and center the paragraph containing `emphasized`.
struct MultiHighlightedText: View {
    struct Mark {
        let range: Range<String.Index>
        let color: Color
    }

    let text: String
    let marks: [Mark]
    var emphasized: Range<String.Index>?

    private var paragraphs: [Range<String.Index>] { TextParagraphs.ranges(in: text) }

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
        for mark in marks {
            paint(&a, paragraphRange: paragraphRange, markRange: mark.range, color: mark.color, opacity: 0.30)
        }
        if let emphasized {
            paint(&a, paragraphRange: paragraphRange, markRange: emphasized, color: .accentColor, opacity: 0.55)
        }
        return a
    }

    /// Intersects `markRange` (an index range into the full `text`) with
    /// `paragraphRange`, then paints the overlapping part relative to the
    /// paragraph's own `AttributedString`.
    private func paint(
        _ a: inout AttributedString, paragraphRange: Range<String.Index>,
        markRange: Range<String.Index>, color: Color, opacity: Double
    ) {
        let lower = max(markRange.lowerBound, paragraphRange.lowerBound)
        let upper = min(markRange.upperBound, paragraphRange.upperBound)
        guard lower < upper else { return }
        let lowerOffset = text.distance(from: paragraphRange.lowerBound, to: lower)
        let upperOffset = text.distance(from: paragraphRange.lowerBound, to: upper)
        guard lowerOffset >= 0, upperOffset <= a.characters.count, lowerOffset < upperOffset else { return }
        let aLower = a.index(a.startIndex, offsetByCharacters: lowerOffset)
        let aUpper = a.index(a.startIndex, offsetByCharacters: upperOffset)
        a[aLower..<aUpper].backgroundColor = color.opacity(opacity)
    }
}

extension SoftHintKind {
    /// Highlight color per hint type.
    var highlightColor: Color {
        switch self {
        case .longSentence: return .yellow
        case .repeatedRoot: return .orange
        case .cliche:       return .pink
        }
    }

    var title: String {
        switch self {
        case .longSentence: return "Длинное предложение"
        case .repeatedRoot: return "Повтор однокоренного"
        case .cliche:       return "Штамп"
        }
    }
}
