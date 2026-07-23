import Testing
@testable import SEOContentCreator

struct PreparationDestinationTests {
    @Test func readerIntentPrecedesSemantics() {
        #expect(PreparationDestination.allCases == [.readerIntent, .semantics])
    }

    @Test func destinationsKeepUserFacingTitles() {
        #expect(PreparationDestination.readerIntent.title == "Задача читателя")
        #expect(PreparationDestination.semantics.title == "Семантика")
    }
}
