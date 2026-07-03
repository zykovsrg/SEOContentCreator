import SwiftUI

/// Renders Markdown headings, lists and bold text using the same block model
/// used for Google Docs publishing (`MarkdownDocParser`), instead of showing
/// raw "## " syntax as plain text.
struct MarkdownBlocksView: View {
    var text: String
    /// Applied to each block's Text before `.textSelection`, since `.strikethrough`
    /// is only defined on `Text` and this view's body has no single `Text` to modify from outside.
    var strikethrough: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(numberedBlocks.enumerated()), id: \.offset) { _, item in
                blockText(item.block, number: item.number)
                    .font(font(for: item.block.style))
                    .strikethrough(strikethrough)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private struct NumberedBlock {
        let block: DocBlock
        let number: Int?
    }

    private var numberedBlocks: [NumberedBlock] {
        var result: [NumberedBlock] = []
        var counter = 0
        for block in MarkdownDocParser.parse(text) {
            if block.listType == .numbered {
                counter += 1
                result.append(NumberedBlock(block: block, number: counter))
            } else {
                counter = 0
                result.append(NumberedBlock(block: block, number: nil))
            }
        }
        return result
    }

    private func blockText(_ block: DocBlock, number: Int?) -> Text {
        let prefix: String
        switch block.listType {
        case .bullet:   prefix = "•  "
        case .numbered: prefix = "\(number ?? 1).  "
        case nil:       prefix = ""
        }
        return Text(prefix) + styledText(block)
    }

    private func styledText(_ block: DocBlock) -> Text {
        guard !block.boldRanges.isEmpty else { return Text(block.text) }
        let chars = Array(block.text)
        var result = Text("")
        var cursor = 0
        for range in block.boldRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if range.lowerBound > cursor {
                result = result + Text(String(chars[cursor..<range.lowerBound]))
            }
            result = result + Text(String(chars[range.lowerBound..<range.upperBound])).bold()
            cursor = range.upperBound
        }
        if cursor < chars.count {
            result = result + Text(String(chars[cursor...]))
        }
        return result
    }

    private func font(for style: DocParagraphStyle) -> Font {
        switch style {
        case .heading1: return .title.bold()
        case .heading2: return .title2.bold()
        case .heading3: return .title3.bold()
        case .normal:   return .body
        }
    }
}
