import Testing
import Foundation
@testable import SEOContentCreator

struct StagePromptIntentMigrationTests {
    @Test func upgradesCustomizedStructureWithoutReplacingExistingText() {
        let original = "Мой изменённый промт структуры. Верни Markdown."
        let upgraded = StagePromptIntentMigration.upgrade(original, for: .structure)
        #expect(upgraded.contains(original))
        #expect(upgraded.contains("{{задача_читателя}}"))
        #expect(upgraded.contains("{{семантика}}"))
    }

    @Test func upgradeIsIdempotent() {
        let first = StagePromptIntentMigration.upgrade("Мой промт", for: .seoCheck)
        let second = StagePromptIntentMigration.upgrade(first, for: .seoCheck)
        #expect(second == first)
        #expect(second.components(separatedBy: "{{задача_читателя}}").count == 2)
    }

    @Test func unrelatedStageIsUnchanged() {
        #expect(StagePromptIntentMigration.upgrade("Фактчек", for: .factCheck) == "Фактчек")
    }

    // MARK: - Anchor-splice path (real v8-era anchors, not just append-fallback)

    @Test func upgradesStructureBySplicingAfterRealAnchorAtEndOfPrompt() {
        // Real v8-era `.structure` prompt: the anchor is the very last sentence,
        // preceded by the operator's own customized instructions.
        let before = """
        Подготовь структуру текста для посадочной страницы. Только структуру, без текста статьи.

        Тема: {{тема}}
        Мои личные требования: пиши только на «ты», не используй канцелярит. Не добавляй ключевые запросы. Формат — Markdown.
        """
        let anchor = "Не добавляй ключевые запросы. Формат — Markdown."
        // Sanity check: the anchor sits inside `before`, at the very end.
        #expect(before.hasSuffix(anchor))

        let upgraded = StagePromptIntentMigration.upgrade(before, for: .structure)

        let marker = "<!-- reader-intent-v1:structure -->"
        #expect(upgraded.hasPrefix(before))
        #expect(upgraded.contains(marker))
        #expect(upgraded.contains("{{задача_читателя}}"))
        #expect(upgraded.contains("{{семантика}}"))
        #expect(upgraded.contains("Верни только структуру H1/H2/H3 с пометками; карту задачи в результат не включай."))

        guard let anchorRange = upgraded.range(of: anchor),
              let markerRange = upgraded.range(of: marker) else {
            Issue.record("expected anchor and marker ranges to be found")
            return
        }
        // The addition must start right after the anchor (with nothing but the
        // separator in between), not be tacked onto some unrelated trailing text.
        #expect(anchorRange.upperBound == before.endIndex)
        #expect(markerRange.lowerBound > anchorRange.upperBound)
        let between = upgraded[anchorRange.upperBound..<markerRange.lowerBound]
        #expect(between == "\n\n")
    }

    @Test func upgradesDraftBySplicingAfterRealAnchorMidPrompt() {
        // Real v8-era `.draft` prompt: `{{структура}}` sits mid-document, with
        // the operator's own "Правила текста" block still following it.
        let before = """
        Напиши текст строго по утверждённой структуре.

        Тема: {{тема}}

        Структура (план статьи):
        {{структура}}
        """
        let after = """


        Мои личные правила текста:
        - Никогда не используй слово «инновационный».
        - В конце добавь раздел «## Источники».
        """
        let original = before + after
        let anchor = "{{структура}}"
        #expect(original.range(of: anchor) != nil)

        let upgraded = StagePromptIntentMigration.upgrade(original, for: .draft)

        let marker = "<!-- reader-intent-v1:draft -->"
        #expect(upgraded.contains(marker))
        #expect(upgraded.contains("{{задача_читателя}}"))
        #expect(upgraded.contains("Используй карту как рамку текста: каждый раздел помогает достичь критерия полезного ответа или снять значимый барьер. Саму карту в статью не включай."))

        guard let beforeRange = upgraded.range(of: before),
              let anchorRange = upgraded.range(of: anchor),
              let markerRange = upgraded.range(of: marker),
              let afterRange = upgraded.range(of: after) else {
            Issue.record("expected before/anchor/marker/after ranges to be found")
            return
        }
        // 1. Everything before the anchor is preserved and precedes the addition.
        #expect(beforeRange.upperBound == anchorRange.upperBound)
        // 3. The addition is spliced in right after the anchor — proven because
        //    the operator's trailing "Мои личные правила" text is still the
        //    very end of the string, not swallowed under an appended block.
        #expect(anchorRange.upperBound < markerRange.lowerBound)
        #expect(markerRange.upperBound < afterRange.lowerBound)
        #expect(upgraded.hasSuffix(after))
    }

    @Test func upgradesSemanticsInTextBySplicingAfterRealAnchorMidPrompt() {
        // Real v8-era `.semanticsInText` prompt: "Текущий текст:" precedes the
        // `{{текущий_текст}}` placeholder and the operator's own extra rules.
        let before = """
        Встрой ключевые запросы в текст естественно. Учитывай частотность. Допиши/поправь H1, сгенерируй Title и Description.

        Текущий текст:
        """
        let after = """

        {{текущий_текст}}

        Мои личные требования: Description не длиннее 160 символов, H1 без восклицательных знаков.
        """
        let original = before + after
        let anchor = "Текущий текст:"

        let upgraded = StagePromptIntentMigration.upgrade(original, for: .semanticsInText)

        let marker = "<!-- reader-intent-v1:semanticsInText -->"
        #expect(upgraded.contains(marker))
        #expect(upgraded.contains("{{задача_читателя}}"))
        #expect(upgraded.contains("H1, Title и Description должны отражать практическую задачу читателя без неподтверждённых обещаний."))

        guard let beforeRange = upgraded.range(of: before),
              let anchorRange = upgraded.range(of: anchor),
              let markerRange = upgraded.range(of: marker),
              let afterRange = upgraded.range(of: after) else {
            Issue.record("expected before/anchor/marker/after ranges to be found")
            return
        }
        #expect(beforeRange.upperBound == anchorRange.upperBound)
        #expect(anchorRange.upperBound < markerRange.lowerBound)
        #expect(markerRange.upperBound < afterRange.lowerBound)
        // Operator's trailing custom requirement stays at the very end — proof
        // the addition was spliced right after the anchor, not appended last.
        #expect(upgraded.hasSuffix(after))
    }

    @Test func upgradesSeoCheckBySplicingAfterRealAnchorMidPrompt() {
        // Real v8-era `.seoCheck` prompt: "Текст:" precedes the current text
        // placeholder, with the operator's own scoring notes after it.
        let before = """
        Проверь текст на соответствие SEO-требованиям. Не переписывай — верни список замечаний.

        H1: {{текущий_h1}}
        Title: {{текущий_title}}
        Description: {{текущий_description}}

        Текст:
        """
        let after = """

        {{текущий_текст}}

        Мои личные пометки: если объём меньше 3000 знаков — всегда пиши замечание в категории «Объём».
        """
        let original = before + after
        let anchor = "Текст:"

        let upgraded = StagePromptIntentMigration.upgrade(original, for: .seoCheck)

        let marker = "<!-- reader-intent-v1:seoCheck -->"
        #expect(upgraded.contains(marker))
        #expect(upgraded.contains("{{задача_читателя}}"))
        #expect(upgraded.contains("Проверь, отвечает ли страница практическому интенту и покрывает ли выбранные в карте типы информации. Не требуй категории, которые в карте не выбраны. Для замечаний по этим критериям используй категории «Интент» и «Полнота»."))

        guard let beforeRange = upgraded.range(of: before),
              let anchorRange = upgraded.range(of: anchor),
              let markerRange = upgraded.range(of: marker),
              let afterRange = upgraded.range(of: after) else {
            Issue.record("expected before/anchor/marker/after ranges to be found")
            return
        }
        #expect(beforeRange.upperBound == anchorRange.upperBound)
        #expect(anchorRange.upperBound < markerRange.lowerBound)
        #expect(markerRange.upperBound < afterRange.lowerBound)
        #expect(upgraded.hasSuffix(after))
    }
}
