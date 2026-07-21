import Foundation

/// Decides whether an edit to a role or context block actually changed
/// anything, so saving a stage prompt does not bump a shared role/block
/// version (and touch every other stage that uses it) when the user only
/// edited this stage's own prompt.
enum SharedFieldUpdate {
    struct RoleChange {
        let mandate: String
        let blockKeys: [String]
        let version: Int
    }

    static func roleUpdate(current: AIRole, mandate: String, blockKeys: [String]) -> RoleChange? {
        guard current.mandate != mandate || current.blockKeys != blockKeys else { return nil }
        return RoleChange(mandate: mandate, blockKeys: blockKeys, version: current.version + 1)
    }

    struct BlockChange {
        let text: String
        let version: Int
    }

    static func blockUpdate(current: ContextBlock, text: String) -> BlockChange? {
        guard current.text != text else { return nil }
        return BlockChange(text: text, version: current.version + 1)
    }
}
