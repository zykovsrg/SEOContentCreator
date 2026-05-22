import Foundation

enum BriefValidation {
    static func canCreate(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canStartDraft(title: String, direction: String) -> Bool {
        canCreate(title: title)
        && !direction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
