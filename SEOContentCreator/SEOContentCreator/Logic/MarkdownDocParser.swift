import Foundation

enum DocParagraphStyle: Equatable {
    case normal, heading1, heading2, heading3
}

enum DocListType: Equatable {
    case bullet, numbered
}

struct DocBlock: Equatable {
    var style: DocParagraphStyle
    var listType: DocListType?
    var text: String
    /// Диапазоны жирного в `text`, в индексах символов (Character offsets).
    var boldRanges: [Range<Int>]
}

enum MarkdownDocParser {
    static func parse(_ markdown: String) -> [DocBlock] {
        var blocks: [DocBlock] = []
        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            var style: DocParagraphStyle = .normal
            var listType: DocListType? = nil
            var content = line

            if line.hasPrefix("### ") { style = .heading3; content = String(line.dropFirst(4)) }
            else if line.hasPrefix("## ") { style = .heading2; content = String(line.dropFirst(3)) }
            else if line.hasPrefix("# ") { style = .heading1; content = String(line.dropFirst(2)) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { listType = .bullet; content = String(line.dropFirst(2)) }
            else if let m = numberedPrefixLength(line) { listType = .numbered; content = String(line.dropFirst(m)) }

            let (plain, bold) = extractBold(content)
            blocks.append(DocBlock(style: style, listType: listType, text: plain, boldRanges: bold))
        }
        return blocks
    }

    /// Длина префикса вида "12. " если строка нумерованный пункт, иначе nil.
    private static func numberedPrefixLength(_ line: String) -> Int? {
        var idx = line.startIndex
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber { idx = line.index(after: idx); digits += 1 }
        guard digits > 0, idx < line.endIndex, line[idx] == "." else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        return digits + 2 // цифры + "." + " "
    }

    /// Убирает **…** и *…*, возвращает плоский текст и диапазоны жирного (в Character-индексах).
    private static func extractBold(_ input: String) -> (String, [Range<Int>]) {
        var result = ""
        var ranges: [Range<Int>] = []
        let chars = Array(input)
        var i = 0
        var bold = false
        var boldStart = 0
        while i < chars.count {
            if chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "*" {
                if !bold { bold = true; boldStart = result.count }
                else { bold = false; ranges.append(boldStart..<result.count) }
                i += 2
                continue
            }
            if chars[i] == "*" {
                i += 1
                continue
            }
            result.append(chars[i])
            i += 1
        }
        if bold { ranges.append(boldStart..<result.count) }
        return (result, ranges)
    }
}
