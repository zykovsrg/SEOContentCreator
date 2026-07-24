import Testing
@testable import SEOContentCreator

struct StreamingTailTests {
    @Test func defaultWindowStaysAboutOneScreenful() {
        var long = ""
        for i in 0..<500 { long += "Строка \(i).\n" }
        let tail = long.streamingTail()
        // The live window must stay small: layout of this string is redone on every
        // streamed update, so an oversized default silently slows generation down.
        #expect(tail.count <= 1202)
        #expect(long.hasSuffix(String(tail.dropFirst(2))))
    }

    @Test func shortTextIsReturnedUnchanged() {
        let text = "line1\nline2\nline3"
        #expect(text.streamingTail(maxChars: 4000) == text)
    }

    @Test func exactlyAtLimitIsUnchanged() {
        let text = String(repeating: "x", count: 100)
        #expect(text.streamingTail(maxChars: 100) == text)
    }

    @Test func longTextIsBoundedAndKeepsTheEnding() {
        var long = ""
        for i in 0..<500 { long += "Строка \(i).\n" }
        let tail = long.streamingTail(maxChars: 100)
        // Bounded to about maxChars (+ the "…\n" marker).
        #expect(tail.count <= 102)
        // The tail is the real ending of the stream, not the beginning.
        #expect(long.hasSuffix(String(tail.dropFirst(2))))
    }

    @Test func truncatedTailDropsThePartialFirstLine() {
        var long = ""
        for i in 0..<500 { long += "Строка номер \(i).\n" }
        let tail = long.streamingTail(maxChars: 60)
        #expect(tail.hasPrefix("…\n"))
        let shown = String(tail.dropFirst(2))
        #expect(long.hasSuffix(shown))
        // The shown text begins right after a newline in the original (whole-line boundary).
        let start = long.index(long.endIndex, offsetBy: -shown.count)
        #expect(start == long.startIndex || long[long.index(before: start)] == "\n")
    }

    @Test func truncatedWindowWithoutNewlineIsPrefixedWithEllipsis() {
        let noNewlines = String(repeating: "a", count: 300)
        let tail = noNewlines.streamingTail(maxChars: 100)
        #expect(tail == "…" + String(repeating: "a", count: 100))
    }
}
