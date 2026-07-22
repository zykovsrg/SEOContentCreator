import Testing
@testable import SEOContentCreator

struct PromptPersonalDefaultsTests {
    @Test func saveUpdatesLiveStateAndFullPersonalDefault() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "old")
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "old role", blockKeys: [])
        let block = ContextBlock(key: "sources", title: "Источники", text: "old block")
        let state = PromptEditorState(
            userPromptTemplate: "new", modelName: "gpt-5.5", temperature: 0.3,
            maxTokens: 12000, reasoningEffort: "high", mandate: "new role",
            enabledBlockKeys: ["sources"], blockTexts: ["sources": "new block"]
        )
        PromptPersonalDefaultsService.saveAsPersonalDefault(
            state, template: template, role: role, blocks: [block]
        )
        #expect(template.userPromptTemplate == "new")
        #expect(template.personalDefaultUserPromptTemplate == "new")
        #expect(template.personalDefaultReasoningEffort == "high")
        #expect(role.personalDefaultMandate == "new role")
        #expect(role.personalDefaultBlockKeys == ["sources"])
        #expect(block.personalDefaultText == "new block")
        #expect(template.hasPersonalDefault && role.hasPersonalDefault && block.hasPersonalDefault)
    }

    @Test func personalRestoreReturnsValueWithoutMutatingLiveObjects() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "live")
        template.hasPersonalDefault = true
        template.personalDefaultUserPromptTemplate = "personal"
        template.personalDefaultModelName = "gpt-4.1"
        template.personalDefaultTemperature = 0.6
        template.personalDefaultMaxTokens = 8000
        let state = PromptPersonalDefaultsService.personalDefaultState(
            template: template, role: nil, blocks: []
        )
        #expect(state?.userPromptTemplate == "personal")
        #expect(template.userPromptTemplate == "live")
    }

    @Test func factoryRestoreReturnsCurrentCodeDefaultsWithoutMutation() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "live")
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "live role", blockKeys: [])
        let block = ContextBlock(key: "sources", title: "Источники", text: "live block")
        let state = PromptPersonalDefaultsService.factoryState(stage: .draft, role: role, blocks: [block])
        #expect(state.userPromptTemplate == StageTemplateDefaults.content(for: .draft).userPromptTemplate)
        #expect(state.mandate == RoleDefaults.defaultForKey("author")?.mandate)
        #expect(state.blockTexts["sources"] == ContextBlockDefaults.defaultForKey("sources")?.text)
        #expect(template.userPromptTemplate == "live")
    }

    @Test func savingOnlyStageFieldsDoesNotBumpUnchangedSharedVersions() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "old")
        let role = AIRole(key: "author", name: "ИИ-автор", mandate: "same", blockKeys: ["sources"], version: 4)
        let block = ContextBlock(key: "sources", title: "Источники", text: "same block", version: 7)
        let state = PromptEditorState(
            userPromptTemplate: "new", modelName: "gpt-4.1", temperature: 0.6,
            maxTokens: 8000, reasoningEffort: nil, mandate: "same",
            enabledBlockKeys: ["sources"], blockTexts: ["sources": "same block"]
        )
        PromptPersonalDefaultsService.saveAsPersonalDefault(
            state, template: template, role: role, blocks: [block]
        )
        #expect(role.version == 4)
        #expect(block.version == 7)
    }

    @Test func captureIfMissingNeverOverwritesExistingPersonalDefault() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "live v1")
        PromptPersonalDefaultsService.captureIfMissing(template: template, role: nil, blocks: [])
        template.userPromptTemplate = "live v2"
        PromptPersonalDefaultsService.captureIfMissing(template: template, role: nil, blocks: [])
        #expect(template.personalDefaultUserPromptTemplate == "live v1")
    }
}
