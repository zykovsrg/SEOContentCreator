import Testing
@testable import SEOContentCreator

struct ParagraphDiffTests {
    @Test func identicalTextsAllUnchanged() {
        let old = "Абзац 1\n\nАбзац 2"
        let new = "Абзац 1\n\nАбзац 2"
        let lines = ParagraphDiff.diff(old: old, new: new)
        #expect(lines.allSatisfy { $0.kind == .unchanged })
        #expect(lines.count == 2)
    }

    @Test func addedParagraphMarked() {
        let old = "Абзац 1"
        let new = "Абзац 1\n\nАбзац 2"
        let lines = ParagraphDiff.diff(old: old, new: new)
        #expect(lines.contains { $0.kind == .added && $0.text == "Абзац 2" })
        #expect(lines.contains { $0.kind == .unchanged && $0.text == "Абзац 1" })
    }

    @Test func removedParagraphMarked() {
        let old = "Абзац 1\n\nАбзац 2"
        let new = "Абзац 1"
        let lines = ParagraphDiff.diff(old: old, new: new)
        #expect(lines.contains { $0.kind == .removed && $0.text == "Абзац 2" })
    }

    @Test func newParagraphsHelperReturnsOnlyNewSide() {
        let old = "A\n\nB"
        let new = "A\n\nC"
        let right = ParagraphDiff.newSide(old: old, new: new)
        #expect(right.contains { $0.kind == .added && $0.text == "C" })
        #expect(right.contains { $0.kind == .unchanged && $0.text == "A" })
        #expect(right.allSatisfy { $0.kind != .removed })
    }

    @Test func oldSideHelperReturnsOnlyOldSide() {
        let old = "A\n\nB"
        let new = "A\n\nC"
        let left = ParagraphDiff.oldSide(old: old, new: new)
        #expect(left.contains { $0.kind == .removed && $0.text == "B" })
        #expect(left.contains { $0.kind == .unchanged && $0.text == "A" })
        #expect(left.allSatisfy { $0.kind != .added })
    }

    @Test func oldSideIdenticalTextsAllUnchanged() {
        let left = ParagraphDiff.oldSide(old: "A\n\nB", new: "A\n\nB")
        #expect(left.count == 2)
        #expect(left.allSatisfy { $0.kind == .unchanged })
    }
}
