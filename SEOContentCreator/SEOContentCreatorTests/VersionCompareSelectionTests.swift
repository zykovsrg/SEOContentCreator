import Testing
import Foundation
@testable import SEOContentCreator

struct VersionCompareSelectionTests {
    private let a = UUID(), b = UUID(), c = UUID()

    @Test func appendsWhenUnderLimit() {
        let r = compareSelectionToggle(current: [a], tapped: b)
        #expect(r == [a, b])
    }

    @Test func togglingSelectedRemovesIt() {
        let r = compareSelectionToggle(current: [a, b], tapped: a)
        #expect(r == [b])
    }

    @Test func thirdSelectionEvictsEarliest() {
        let r = compareSelectionToggle(current: [a, b], tapped: c)
        #expect(r == [b, c])
    }
}
