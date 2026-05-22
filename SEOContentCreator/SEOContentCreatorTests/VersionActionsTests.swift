import Testing
@testable import SEOContentCreator

struct VersionActionsTests {
    @Test func acceptsSelectedNewParagraphsKeepsRestFromOld() {
        let old = "A\n\nB\n\nC"
        let new = "A2\n\nB2\n\nC2"
        // accept only paragraphs at index 0 and 2 from new; index 1 stays old
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [0, 2])
        #expect(hybrid == "A2\n\nB\n\nC2")
    }

    @Test func emptySelectionReturnsOld() {
        let old = "A\n\nB"
        let new = "X\n\nY"
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [])
        #expect(hybrid == "A\n\nB")
    }

    @Test func fullSelectionReturnsNew() {
        let old = "A\n\nB"
        let new = "X\n\nY"
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [0, 1])
        #expect(hybrid == "X\n\nY")
    }
}
