import Foundation

struct EditorMetrics: Equatable {
    let charactersWithSpaces: Int
    let words: Int
    let commercialBlocks: Int
    let progress: Double?

    static func compute(text: String, targetVolume: Int?) -> EditorMetrics {
        let segments = CommercialBlockSplitter.split(text)
        let visibleMarkdown = segments.map(\.text).joined(separator: "\n\n")
        let visibleText = MarkdownDocParser.parse(visibleMarkdown).map(\.text).joined(separator: "\n\n")
        let characters = visibleText.count
        let words = visibleText
            .split { !$0.isLetter && !$0.isNumber }
            .count
        let commercialBlocks = segments.filter(\.isCommercial).count
        let progress = targetVolume
            .flatMap { target -> Double? in
                guard target > 0 else { return nil }
                return min(Double(characters) / Double(target), 1)
            }

        return EditorMetrics(
            charactersWithSpaces: characters,
            words: words,
            commercialBlocks: commercialBlocks,
            progress: progress
        )
    }
}
