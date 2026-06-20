import Testing
@testable import SEOContentCreator

struct ImagePromptBuilderTests {
    @Test func subjectSubstitutesThemeAndFragment() {
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let template = ImagePromptTemplate(kind: .illustration,
            userPromptTemplate: "Статья: {{тема}}\nФрагмент:\n{{выделенный_фрагмент}}")
        let subject = ImagePromptBuilder().subject(template: template, topic: topic, fragment: "Симптомы болезни")
        #expect(subject.contains("Рак простаты"))
        #expect(subject.contains("Симптомы болезни"))
        #expect(!subject.contains("{{"))
    }

    @Test func composeAppendsStyleText() {
        let preset = ImageStylePreset(name: "Бренд", styleText: "Палитра: #007AC0")
        let result = ImagePromptBuilder().compose(subject: "Сюжет", preset: preset)
        #expect(result == "Сюжет\n\nПалитра: #007AC0")
    }

    @Test func composeWithoutPresetReturnsSubject() {
        let result = ImagePromptBuilder().compose(subject: "Сюжет", preset: nil)
        #expect(result == "Сюжет")
    }

    @Test func emptyFragmentLeavesPlaceholderEmpty() {
        let topic = Topic(title: "Тема", articleType: .info)
        let template = ImagePromptTemplate(kind: .illustration, userPromptTemplate: "[{{выделенный_фрагмент}}]")
        let subject = ImagePromptBuilder().subject(template: template, topic: topic, fragment: "")
        #expect(subject == "[]")
    }
}
