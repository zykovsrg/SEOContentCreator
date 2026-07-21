import Foundation

/// Read-only "used elsewhere" facts shown as plaques on the merged stage-prompt
/// editor, so editing a shared role mandate or context block doesn't silently
/// change other stages without warning.
enum PromptCompositionUsage {
    /// Stage titles (canonical pipeline order) whose `roleKey` matches the given
    /// role key. Used for the role-mandate plaque.
    static func stageTitles(forRoleKey roleKey: String) -> [String] {
        PipelineStage.allCases
            .filter { $0.roleKey == roleKey }
            .map(\.title)
    }

    /// Role names (canonical role order) that include the given block key in
    /// their `blockKeys`. Used for the context-block plaque.
    static func roleNames(forBlockKey blockKey: String, in roles: [AIRole]) -> [String] {
        let canonicalOrder = RoleDefaults.all.map(\.key)
        return roles
            .filter { $0.blockKeys.contains(blockKey) }
            .sorted {
                (canonicalOrder.firstIndex(of: $0.key) ?? Int.max)
                    < (canonicalOrder.firstIndex(of: $1.key) ?? Int.max)
            }
            .map(\.name)
    }
}
