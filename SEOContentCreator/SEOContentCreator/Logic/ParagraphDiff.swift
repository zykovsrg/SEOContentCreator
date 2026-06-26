import Foundation

enum ParagraphDiffKind {
    case unchanged
    case added
    case removed
}

struct ParagraphDiffLine: Equatable {
    let text: String
    let kind: ParagraphDiffKind
}

enum ParagraphDiff {
    static func paragraphs(_ s: String) -> [String] {
        s.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Merged diff over paragraphs using a Longest Common Subsequence.
    static func diff(old: String, new: String) -> [ParagraphDiffLine] {
        let a = paragraphs(old)
        let b = paragraphs(new)
        let lcs = lcsTable(a, b)
        var reversed: [ParagraphDiffLine] = []
        var i = a.count, j = b.count
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                reversed.append(ParagraphDiffLine(text: a[i - 1], kind: .unchanged))
                i -= 1; j -= 1
            } else if lcs[i - 1][j] >= lcs[i][j - 1] {
                reversed.append(ParagraphDiffLine(text: a[i - 1], kind: .removed))
                i -= 1
            } else {
                reversed.append(ParagraphDiffLine(text: b[j - 1], kind: .added))
                j -= 1
            }
        }
        while i > 0 { reversed.append(ParagraphDiffLine(text: a[i - 1], kind: .removed)); i -= 1 }
        while j > 0 { reversed.append(ParagraphDiffLine(text: b[j - 1], kind: .added)); j -= 1 }
        return reversed.reversed()
    }

    /// Right-column view: only `.unchanged` and `.added` lines (the new version).
    static func newSide(old: String, new: String) -> [ParagraphDiffLine] {
        diff(old: old, new: new).filter { $0.kind != .removed }
    }

    /// Left-column view: only `.unchanged` and `.removed` lines (the old version).
    static func oldSide(old: String, new: String) -> [ParagraphDiffLine] {
        diff(old: old, new: new).filter { $0.kind != .added }
    }

    private static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if a.isEmpty || b.isEmpty { return table }
        for x in 1...a.count {
            for y in 1...b.count {
                table[x][y] = a[x - 1] == b[y - 1]
                    ? table[x - 1][y - 1] + 1
                    : max(table[x - 1][y], table[x][y - 1])
            }
        }
        return table
    }
}
