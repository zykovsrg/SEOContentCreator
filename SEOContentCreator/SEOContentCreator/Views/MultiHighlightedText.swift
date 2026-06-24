import SwiftUI

/// Read-only text that paints several colored background ranges, with one
/// optional emphasized range drawn stronger. Ranges are `String.Index` ranges
/// into the SAME `text` value passed in.
struct MultiHighlightedText: View {
    struct Mark {
        let range: Range<String.Index>
        let color: Color
    }

    let text: String
    let marks: [Mark]
    var emphasized: Range<String.Index>?

    var body: some View {
        Text(attributed).textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var a = AttributedString(text)
        for mark in marks {
            paint(&a, range: mark.range, color: mark.color, opacity: 0.30)
        }
        if let emphasized {
            paint(&a, range: emphasized, color: .accentColor, opacity: 0.55)
        }
        return a
    }

    /// Maps a `String.Index` range into `text` onto `AttributedString` indices
    /// by character offset (1:1 for plain text) and sets the background color.
    private func paint(_ a: inout AttributedString, range: Range<String.Index>, color: Color, opacity: Double) {
        let lowerOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: range.upperBound)
        guard lowerOffset >= 0, upperOffset <= a.characters.count, lowerOffset < upperOffset else { return }
        let lower = a.index(a.startIndex, offsetByCharacters: lowerOffset)
        let upper = a.index(a.startIndex, offsetByCharacters: upperOffset)
        a[lower..<upper].backgroundColor = color.opacity(opacity)
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
