import Testing
@testable import SEOContentCreator

struct BriefValidationTests {
    @Test func cannotCreateWithEmptyTitle() {
        #expect(BriefValidation.canCreate(title: "") == false)
        #expect(BriefValidation.canCreate(title: "   ") == false)
    }

    @Test func canCreateWithTitle() {
        #expect(BriefValidation.canCreate(title: "Рак простаты") == true)
    }

    @Test func draftRequiresTitleAndDirection() {
        #expect(BriefValidation.canStartDraft(title: "Тема", direction: "") == false)
        #expect(BriefValidation.canStartDraft(title: "", direction: "Лучевая терапия") == false)
        #expect(BriefValidation.canStartDraft(title: "Тема", direction: "Лучевая терапия") == true)
    }
}
