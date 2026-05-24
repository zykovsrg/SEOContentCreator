import Testing
@testable import SEOContentCreator

struct PromptBuilderTests {
    private func draftTemplate() -> StageTemplate {
        StageTemplate(
            stage: .draft,
            systemPrompt: "Ты медицинский автор.",
            userPromptTemplate: "Тема: {{тема}}\nТип: {{тип}}\nОбъём: {{объём}}\nНаправление: {{направление}}\nПреимущества: {{преимущества}}"
        )
    }

    @Test func substitutesBriefVariables() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction, content: "Описание ЛТ")
        let adv = KnowledgeNode(title: "Одно посещение", type: .advantage, content: "Лечение за один визит")
        let topic = Topic(title: "Рак простаты", articleType: .disease, targetVolume: 4000, direction: dir)
        topic.attachedNodes = [adv]

        let result = PromptBuilder().build(template: draftTemplate(), topic: topic, currentText: nil)

        #expect(result.system == "Ты медицинский автор.")
        #expect(result.user.contains("Тема: Рак простаты"))
        #expect(result.user.contains("Тип: Заболевание"))
        #expect(result.user.contains("Объём: 4000"))
        #expect(result.user.contains("Описание ЛТ"))
        #expect(result.user.contains("Лечение за один визит"))
    }

    @Test func unknownPlaceholdersLeftAsIs() {
        let t = StageTemplate(stage: .draft, systemPrompt: "x", userPromptTemplate: "Привет {{неизвестно}}")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(result.user == "Привет {{неизвестно}}")
    }

    @Test func currentTextAndSemanticsSubstituted() {
        let t = StageTemplate(stage: .semanticsInText, systemPrompt: "x",
                              userPromptTemplate: "Текст: {{текущий_текст}}\nЗапросы: {{семантика}}")
        let topic = Topic(title: "T", articleType: .info)
        topic.semantics = ["рак простаты лечение", "лучевая терапия цена"]
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "Готовый текст")
        #expect(result.user.contains("Текст: Готовый текст"))
        #expect(result.user.contains("рак простаты лечение"))
        #expect(result.user.contains("лучевая терапия цена"))
    }

    @Test func substitutesStructure() {
        let t = StageTemplate(stage: .draft, systemPrompt: "x",
                              userPromptTemplate: "План:\n{{структура}}")
        let topic = Topic(title: "T", articleType: .info)
        topic.structureText = "# H1 Рак простаты\n## Введение\n- о чём раздел"
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(result.user.contains("# H1 Рак простаты"))
        #expect(result.user.contains("## Введение"))
    }

    @Test func emptyStructureLeavesPlaceholderEmpty() {
        let t = StageTemplate(stage: .draft, systemPrompt: "x",
                              userPromptTemplate: "План:[{{структура}}]")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(result.user == "План:[]")
    }

    @Test func selectedBlocksAppendedWhenPresent() {
        let t = StageTemplate(stage: .productBlocks, systemPrompt: "x",
                              userPromptTemplate: "Текст: {{текущий_текст}}")
        let topic = Topic(title: "T", articleType: .service)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "Базовый текст",
                                           selectedBlocks: ["CTA", "Блок врача"])
        #expect(result.user.contains("CTA"))
        #expect(result.user.contains("Блок врача"))
    }

    @Test func substitutesKnowledgeBase() {
        let t = StageTemplate(stage: .factCheck, systemPrompt: "x",
                              userPromptTemplate: "Справочник:\n{{база_знаний}}")
        let topic = Topic(title: "T", articleType: .disease)
        let adv = KnowledgeNode(title: "Преимущество", type: .advantage, content: "Лечение за один визит")
        let doc = KnowledgeNode(title: "Усычкин С.В.", type: .doctor, content: "Стаж 20 лет")
        topic.attachedNodes = [adv, doc]
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "текст")
        #expect(result.user.contains("Лечение за один визит"))
        #expect(result.user.contains("Усычкин С.В.: Стаж 20 лет"))
    }

    @Test func prependsRoleContextToSystemPrompt() {
        let t = StageTemplate(stage: .draft, systemPrompt: "Промт этапа", userPromptTemplate: "{{тема}}")
        let topic = Topic(title: "T", articleType: .info)

        let result = PromptBuilder().build(
            template: t,
            topic: topic,
            currentText: nil,
            roleContext: "Контекст роли"
        )

        #expect(result.system == "Контекст роли\n\nПромт этапа")
        #expect(result.user == "T")
    }

    @Test func emptyRoleContextKeepsExistingSystemPrompt() {
        let t = StageTemplate(stage: .draft, systemPrompt: "Промт этапа", userPromptTemplate: "{{тема}}")
        let topic = Topic(title: "T", articleType: .info)

        let result = PromptBuilder().build(
            template: t,
            topic: topic,
            currentText: nil,
            roleContext: ""
        )

        #expect(result.system == "Промт этапа")
        #expect(result.user == "T")
    }
}
