import Testing
@testable import SEOContentCreator

struct SharedFieldUpdateTests {
    @Test func roleUpdateReturnsNilWhenNothingChanged() {
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "Мандат", blockKeys: ["sources"])
        #expect(SharedFieldUpdate.roleUpdate(current: role, mandate: "Мандат", blockKeys: ["sources"]) == nil)
    }

    @Test func roleUpdateBumpsVersionWhenMandateChanged() {
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "Мандат", blockKeys: ["sources"], version: 3)
        let change = SharedFieldUpdate.roleUpdate(current: role, mandate: "Новый мандат", blockKeys: ["sources"])
        #expect(change?.mandate == "Новый мандат")
        #expect(change?.blockKeys == ["sources"])
        #expect(change?.version == 4)
    }

    @Test func roleUpdateBumpsVersionWhenBlockKeysChanged() {
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "Мандат", blockKeys: ["sources"], version: 1)
        let change = SharedFieldUpdate.roleUpdate(current: role, mandate: "Мандат", blockKeys: ["sources", "seoGuidelines"])
        #expect(change?.version == 2)
    }

    @Test func blockUpdateReturnsNilWhenTextUnchanged() {
        let block = ContextBlock(key: "sources", title: "Источники", text: "Текст")
        #expect(SharedFieldUpdate.blockUpdate(current: block, text: "Текст") == nil)
    }

    @Test func blockUpdateBumpsVersionWhenTextChanged() {
        let block = ContextBlock(key: "sources", title: "Источники", text: "Текст", version: 2)
        let change = SharedFieldUpdate.blockUpdate(current: block, text: "Новый текст")
        #expect(change?.text == "Новый текст")
        #expect(change?.version == 3)
    }
}
