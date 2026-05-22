import Foundation

enum BriefValidation {
    static func canCreate(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canStartDraft(title: String, hasDirection: Bool) -> Bool {
        canCreate(title: title) && hasDirection
    }
}
