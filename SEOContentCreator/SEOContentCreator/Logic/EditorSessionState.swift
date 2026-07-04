import Foundation

/// The unified editor's session state: freely editing the full text, running a
/// fragment regeneration, or reviewing its result before accept/reject. Only
/// one fragment operation is ever in flight at a time — there is no queueing.
enum EditorSessionState: Equatable {
    case editing
    case generating(range: NSRange)
    case reviewing(range: NSRange, proposedText: String)

    /// The text view must be read-only in every state except `.editing`, so a
    /// user can't edit around a fragment that's mid-flight or awaiting a
    /// decision.
    var isTextEditable: Bool {
        self == .editing
    }

    var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }

    /// A fragment regeneration can only be triggered while idle, over a
    /// non-empty selection.
    static func canTriggerRegenerate(state: EditorSessionState, hasNonEmptySelection: Bool) -> Bool {
        state == .editing && hasNonEmptySelection
    }

    /// Сохранить/Отмена must wait until any in-flight fragment operation is
    /// resolved (accepted or rejected), so the user can't lose track of a
    /// pending decision.
    static func canCloseSheet(state: EditorSessionState) -> Bool {
        state == .editing
    }
}
