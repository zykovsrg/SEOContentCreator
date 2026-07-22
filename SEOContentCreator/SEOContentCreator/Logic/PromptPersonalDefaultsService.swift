import Foundation

struct PromptEditorState: Equatable {
    var userPromptTemplate: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var reasoningEffort: String?
    var mandate: String
    var enabledBlockKeys: [String]
    var blockTexts: [String: String]
}

/// Builds `PromptEditorState` snapshots for the three sources a stage prompt
/// editor can show: `liveState` reads the values currently in effect,
/// `personalDefaultState` reads the user's saved personal default (or nil if
/// none is fully captured yet), and `factoryState` reads the code-defined
/// factory defaults.
enum PromptPersonalDefaultsService {
    static func liveState(
        template: StageTemplate,
        role: AIRole?,
        blocks: [ContextBlock]
    ) -> PromptEditorState {
        PromptEditorState(
            userPromptTemplate: template.userPromptTemplate,
            modelName: template.modelName,
            temperature: template.temperature,
            maxTokens: template.maxTokens,
            reasoningEffort: template.reasoningEffort,
            mandate: role?.mandate ?? "",
            enabledBlockKeys: role?.blockKeys ?? [],
            blockTexts: Dictionary(uniqueKeysWithValues: blocks.map { ($0.key, $0.text) })
        )
    }

    static func saveAsPersonalDefault(
        _ state: PromptEditorState,
        template: StageTemplate,
        role: AIRole?,
        blocks: [ContextBlock]
    ) {
        let now = Date.now
        template.userPromptTemplate = state.userPromptTemplate
        template.modelName = state.modelName
        template.temperature = state.temperature
        template.maxTokens = state.maxTokens
        template.reasoningEffort = state.reasoningEffort
        template.templateVersion += 1
        template.updatedAt = now
        template.hasPersonalDefault = true
        template.personalDefaultUserPromptTemplate = state.userPromptTemplate
        template.personalDefaultModelName = state.modelName
        template.personalDefaultTemperature = state.temperature
        template.personalDefaultMaxTokens = state.maxTokens
        template.personalDefaultReasoningEffort = state.reasoningEffort
        template.personalDefaultUpdatedAt = now

        if let role {
            if let change = SharedFieldUpdate.roleUpdate(
                current: role,
                mandate: state.mandate,
                blockKeys: state.enabledBlockKeys
            ) {
                role.mandate = change.mandate
                role.blockKeys = change.blockKeys
                role.version = change.version
                role.updatedAt = now
            }
            role.hasPersonalDefault = true
            role.personalDefaultMandate = state.mandate
            role.personalDefaultBlockKeys = state.enabledBlockKeys
            role.personalDefaultUpdatedAt = now
        }

        for block in blocks {
            let text = state.blockTexts[block.key] ?? block.text
            if let change = SharedFieldUpdate.blockUpdate(current: block, text: text) {
                block.text = change.text
                block.version = change.version
                block.updatedAt = now
            }
            block.hasPersonalDefault = true
            block.personalDefaultText = text
            block.personalDefaultUpdatedAt = now
        }
    }

    static func personalDefaultState(
        template: StageTemplate,
        role: AIRole?,
        blocks: [ContextBlock]
    ) -> PromptEditorState? {
        guard template.hasPersonalDefault,
              let user = template.personalDefaultUserPromptTemplate,
              let model = template.personalDefaultModelName,
              let temperature = template.personalDefaultTemperature,
              let maxTokens = template.personalDefaultMaxTokens,
              let blockTexts = personalBlockTexts(blocks)
        else { return nil }
        if let role {
            guard role.hasPersonalDefault, let mandate = role.personalDefaultMandate else { return nil }
            return PromptEditorState(
                userPromptTemplate: user,
                modelName: model,
                temperature: temperature,
                maxTokens: maxTokens,
                reasoningEffort: template.personalDefaultReasoningEffort,
                mandate: mandate,
                enabledBlockKeys: role.personalDefaultBlockKeys,
                blockTexts: blockTexts
            )
        }
        return PromptEditorState(
            userPromptTemplate: user,
            modelName: model,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoningEffort: template.personalDefaultReasoningEffort,
            mandate: "",
            enabledBlockKeys: [],
            blockTexts: blockTexts
        )
    }

    /// Falls back to the role's/block's current live value when no factory
    /// default is registered for its key, since there is no other sensible
    /// default to show in that case.
    static func factoryState(
        stage: PipelineStage,
        role: AIRole?,
        blocks: [ContextBlock]
    ) -> PromptEditorState {
        let template = StageTemplateDefaults.content(for: stage)
        let roleDefault = role.flatMap { RoleDefaults.defaultForKey($0.key) }
        return PromptEditorState(
            userPromptTemplate: template.userPromptTemplate,
            modelName: template.modelName,
            temperature: template.temperature,
            maxTokens: template.maxTokens,
            reasoningEffort: template.reasoningEffort,
            mandate: roleDefault?.mandate ?? role?.mandate ?? "",
            enabledBlockKeys: roleDefault?.blockKeys ?? role?.blockKeys ?? [],
            blockTexts: Dictionary(uniqueKeysWithValues: blocks.map { block in
                (block.key, ContextBlockDefaults.defaultForKey(block.key)?.text ?? block.text)
            })
        )
    }

    static func captureIfMissing(
        template: StageTemplate,
        role: AIRole?,
        blocks: [ContextBlock]
    ) {
        let now = Date.now
        if !template.hasPersonalDefault {
            template.hasPersonalDefault = true
            template.personalDefaultUserPromptTemplate = template.userPromptTemplate
            template.personalDefaultModelName = template.modelName
            template.personalDefaultTemperature = template.temperature
            template.personalDefaultMaxTokens = template.maxTokens
            template.personalDefaultReasoningEffort = template.reasoningEffort
            template.personalDefaultUpdatedAt = now
        }
        if let role, !role.hasPersonalDefault {
            role.hasPersonalDefault = true
            role.personalDefaultMandate = role.mandate
            role.personalDefaultBlockKeys = role.blockKeys
            role.personalDefaultUpdatedAt = now
        }
        for block in blocks where !block.hasPersonalDefault {
            block.hasPersonalDefault = true
            block.personalDefaultText = block.text
            block.personalDefaultUpdatedAt = now
        }
    }

    private static func personalBlockTexts(_ blocks: [ContextBlock]) -> [String: String]? {
        var result: [String: String] = [:]
        for block in blocks {
            guard block.hasPersonalDefault, let text = block.personalDefaultText else { return nil }
            result[block.key] = text
        }
        return result
    }
}
