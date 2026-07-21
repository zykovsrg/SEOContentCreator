import Testing
@testable import SEOContentCreator

struct AppSectionShortcutTests {
    @Test func shortcutsFollowHeaderOrder() {
        #expect(AppSection.allCases.map(\.shortcutKey) == ["1", "2", "3", "4"])
    }

    @Test func keysResolveToTheirSection() {
        #expect(AppSection.section(forShortcutKey: "1") == .contentPlan)
        #expect(AppSection.section(forShortcutKey: "2") == .quickCheck)
        #expect(AppSection.section(forShortcutKey: "3") == .templates)
        #expect(AppSection.section(forShortcutKey: "4") == .knowledgeBase)
    }

    @Test func unboundKeyResolvesToNothing() {
        #expect(AppSection.section(forShortcutKey: "5") == nil)
    }

    @Test func onlyTemplatesStartsTheSecondGroup() {
        #expect(AppSection.allCases.filter(\.startsNewGroup) == [.templates])
    }
}
