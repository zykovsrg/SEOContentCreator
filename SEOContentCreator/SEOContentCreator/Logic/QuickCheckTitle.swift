import Foundation

/// Suggests a topic title from pasted text: first non-empty line, trimmed and
/// capped at 80 characters. Falls back to a fixed label when the text is blank.
enum QuickCheckTitle {
    static func suggest(from text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
        }
        return "Быстрая проверка"
    }
}
