import SwiftUI

/// Plain text that highlights the first occurrence of `highlight` (if any).
struct HighlightedText: View {
    var text: String
    var highlight: String?

    var body: some View {
        Text(attributed).textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var a = AttributedString(text)
        if let highlight, !highlight.isEmpty, let range = a.range(of: highlight) {
            a[range].backgroundColor = .yellow.opacity(0.45)
        }
        return a
    }
}
