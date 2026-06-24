import Foundation
import SwiftData

@Model
final class EditorDictionary {
    var uuid: UUID
    /// Cliché phrases, one per line.
    var clichesText: String
    var longSentenceWordLimit: Int
    var repeatWindowWords: Int
    var version: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        clichesText: String,
        longSentenceWordLimit: Int,
        repeatWindowWords: Int,
        version: Int = 1
    ) {
        self.uuid = UUID()
        self.clichesText = clichesText
        self.longSentenceWordLimit = longSentenceWordLimit
        self.repeatWindowWords = repeatWindowWords
        self.version = version
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension EditorDictionary {
    /// Non-empty, trimmed cliché lines.
    var cliches: [String] {
        clichesText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var settings: SoftHintsSettings {
        SoftHintsSettings(
            longSentenceWordLimit: longSentenceWordLimit,
            repeatWindowWords: repeatWindowWords,
            cliches: cliches
        )
    }
}

enum EditorDictionaryDefaults {
    static let longSentenceWordLimit = 30
    static let repeatWindowWords = 30

    /// Starter cliché list — editable by the user in «Шаблоны».
    static let clichesText = """
    на сегодняшний день
    в наше время
    не секрет, что
    игра стоит свеч
    как известно
    в современном мире
    широкий спектр
    в данной статье
    стоит отметить, что
    """

    static func make() -> EditorDictionary {
        EditorDictionary(
            clichesText: clichesText,
            longSentenceWordLimit: longSentenceWordLimit,
            repeatWindowWords: repeatWindowWords
        )
    }
}
