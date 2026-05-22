import Testing
import Foundation
@testable import SEOContentCreator

struct StageTemplateTests {
    @Test func defaultsAreSet() {
        let t = StageTemplate(stage: .draft, systemPrompt: "Ты автор", userPromptTemplate: "Тема: {{тема}}")
        #expect(t.stageRaw == "draft")
        #expect(t.modelName == "gpt-4.1")
        #expect(t.temperature == 0.6)
        #expect(t.maxTokens == 8000)
        #expect(t.articleTypeRaw == nil)   // universal
        #expect(t.templateVersion == 1)
    }
}
