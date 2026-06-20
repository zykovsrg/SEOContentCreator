import Testing
@testable import SEOContentCreator

struct TemplateVariablesTests {
    @Test func includesCoreVariables() {
        let tokens = TemplateVariables.all.map { $0.token }
        #expect(tokens.contains("{{тема}}"))
        #expect(tokens.contains("{{семантика}}"))
        #expect(tokens.contains("{{база_знаний}}"))
        #expect(tokens.contains("{{текущий_текст}}"))
    }

    @Test func everyVariableHasDescriptionAndSource() {
        for v in TemplateVariables.all {
            #expect(!v.description.isEmpty)
            #expect(!v.source.isEmpty)
        }
    }

    @Test func includesIllustrationFragment() {
        #expect(TemplateVariables.all.contains { $0.token == "{{выделенный_фрагмент}}" })
    }
}
