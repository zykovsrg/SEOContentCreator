import Foundation

enum SoftHintKind: String {
    case longSentence
    case repeatedRoot
    case cliche
}

struct SoftHint: Identifiable {
    let id = UUID()
    let kind: SoftHintKind
    let range: Range<String.Index>
    let message: String
}

struct SoftHintsSettings {
    var longSentenceWordLimit: Int
    var repeatWindowWords: Int
    var cliches: [String]

    static let `default` = SoftHintsSettings(
        longSentenceWordLimit: 30, repeatWindowWords: 30, cliches: []
    )
}

enum SoftHints {
    /// Deterministic order: long sentences → repeated roots → clichés.
    static func analyze(text: String, settings: SoftHintsSettings) -> [SoftHint] {
        longSentenceHints(text, limit: settings.longSentenceWordLimit)
        + repeatedRootHints(text, window: settings.repeatWindowWords)
        + clicheHints(text, cliches: settings.cliches)
    }

    // MARK: Long sentences

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "…", "\n"]

    static func longSentenceHints(_ text: String, limit: Int) -> [SoftHint] {
        sentenceRanges(text).compactMap { range in
            let count = wordRanges(in: text, range: range).count
            guard count > limit else { return nil }
            return SoftHint(
                kind: .longSentence,
                range: range,
                message: "Длинное предложение: \(count) слов. Стоит разбить."
            )
        }
    }

    /// Sentence ranges, split on `.!?…` and newlines, each trimmed of surrounding whitespace.
    static func sentenceRanges(_ text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            if sentenceTerminators.contains(text[i]) {
                let end = text.index(after: i)
                if let r = trimmedRange(text, start..<end) { result.append(r) }
                start = end
            }
            i = text.index(after: i)
        }
        if start < text.endIndex, let r = trimmedRange(text, start..<text.endIndex) {
            result.append(r)
        }
        return result
    }

    /// Word ranges (maximal runs of letters/digits) inside `range`.
    static func wordRanges(in text: String, range: Range<String.Index>) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var wordStart: String.Index?
        var i = range.lowerBound
        while i < range.upperBound {
            let c = text[i]
            if c.isLetter || c.isNumber {
                if wordStart == nil { wordStart = i }
            } else if let s = wordStart {
                result.append(s..<i); wordStart = nil
            }
            i = text.index(after: i)
        }
        if let s = wordStart { result.append(s..<range.upperBound) }
        return result
    }

    /// Trims leading/trailing whitespace & newlines; nil if the result is empty.
    private static func trimmedRange(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace || text[lower].isNewline {
            lower = text.index(after: lower)
        }
        while lower < upper {
            let before = text.index(before: upper)
            if text[before].isWhitespace || text[before].isNewline { upper = before } else { break }
        }
        return lower < upper ? lower..<upper : nil
    }

    // MARK: Repeated roots

    private static let minRootWordLength = 5
    private static let rootPrefixLength = 5

    static func repeatedRootHints(_ text: String, window: Int) -> [SoftHint] {
        let allWords = wordRanges(in: text, range: text.startIndex..<text.endIndex)
        var lastIndex: [String: Int] = [:]
        var lastRange: [String: Range<String.Index>] = [:]
        var hints: [SoftHint] = []
        for (i, r) in allWords.enumerated() {
            let raw = String(text[r])
            let norm = normalized(raw)
            guard norm.count >= minRootWordLength else { continue }
            let root = String(norm.prefix(rootPrefixLength))
            if let j = lastIndex[root], i - j <= window {
                let prev = lastRange[root].map { String(text[$0]) } ?? ""
                hints.append(SoftHint(
                    kind: .repeatedRoot,
                    range: r,
                    message: "Повтор однокоренного рядом: «\(raw)» и «\(prev)»."
                ))
            }
            lastIndex[root] = i
            lastRange[root] = r
        }
        return hints
    }

    /// Lowercase + ё→е so that "Ёлка"/"елка" share a root.
    static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    // MARK: Clichés

    static func clicheHints(_ text: String, cliches: [String]) -> [SoftHint] {
        var hints: [SoftHint] = []
        for entry in cliches {
            let phrase = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let found = text.range(
                      of: phrase,
                      options: [.caseInsensitive, .diacriticInsensitive],
                      range: searchStart..<text.endIndex
                  ) {
                if isWordBoundaryMatch(text, found) {
                    hints.append(SoftHint(
                        kind: .cliche,
                        range: found,
                        message: "Штамп: «\(phrase)». Лучше переформулировать."
                    ))
                }
                searchStart = found.upperBound
            }
        }
        return hints
    }

    /// True when the match is not glued to a letter/digit on either side.
    private static func isWordBoundaryMatch(_ text: String, _ range: Range<String.Index>) -> Bool {
        let beforeOK: Bool
        if range.lowerBound == text.startIndex {
            beforeOK = true
        } else {
            let b = text[text.index(before: range.lowerBound)]
            beforeOK = !(b.isLetter || b.isNumber)
        }
        let afterOK: Bool
        if range.upperBound == text.endIndex {
            afterOK = true
        } else {
            let a = text[range.upperBound]
            afterOK = !(a.isLetter || a.isNumber)
        }
        return beforeOK && afterOK
    }
}
