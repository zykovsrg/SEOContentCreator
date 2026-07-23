import Testing
@testable import SEOContentCreator

struct PromptBuilderTests {
    private func draftTemplate() -> StageTemplate {
        StageTemplate(
            stage: .draft,
            userPromptTemplate: "Тема: {{тема}}\nТип: {{тип}}\nОбъём: {{объём}}\nНаправление: {{направление}}\nПреимущества: {{преимущества}}"
        )
    }

    @Test func substitutesBriefVariables() {
        let dir = KnowledgeNode(title: "Лучевая терапия", type: .direction, content: "Описание ЛТ")
        let adv = KnowledgeNode(title: "Одно посещение", type: .advantage, content: "Лечение за один визит")
        let topic = Topic(title: "Рак простаты", articleType: .disease, targetVolume: 4000, direction: dir)
        topic.attachedNodes = [adv]

        let result = PromptBuilder().build(template: draftTemplate(), topic: topic, currentText: nil)

        #expect(result.user.contains("Тема: Рак простаты"))
        #expect(result.user.contains("Тип: Заболевание"))
        #expect(result.user.contains("Объём: 4000"))
        #expect(result.user.contains("Описание ЛТ"))
        #expect(result.user.contains("Лечение за один визит"))
    }

    @Test func unknownPlaceholdersLeftAsIs() {
        let t = StageTemplate(stage: .draft, userPromptTemplate: "Привет {{неизвестно}}")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(result.user == "Привет {{неизвестно}}")
    }

    @Test func currentTextAndSemanticsSubstituted() {
        let t = StageTemplate(stage: .semanticsInText, userPromptTemplate: "Текст: {{текущий_текст}}\nЗапросы: {{семантика}}")
        let topic = Topic(title: "T", articleType: .info)
        topic.semantics = ["рак простаты лечение", "лучевая терапия цена"]
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "Готовый текст")
        #expect(result.user.contains("Текст: Готовый текст"))
        #expect(result.user.contains("рак простаты лечение"))
        #expect(result.user.contains("лучевая терапия цена"))
    }

    @Test func semanticKeywordDecisionsDriveSemanticsPlaceholder() {
        let t = StageTemplate(stage: .semanticsInText, userPromptTemplate: "Запросы:\n{{семантика}}")
        let topic = Topic(title: "T", articleType: .info)
        topic.semanticKeywords = [
            SemanticKeyword(text: "МРТ лёгких", userDecision: .accepted),
            SemanticKeyword(text: "КТ лёгких", userDecision: .required),
            SemanticKeyword(text: "отклонённый", userDecision: .rejected)
        ]

        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)

        #expect(result.user.contains("МРТ лёгких"))
        #expect(result.user.contains("КТ лёгких (обязательный запрос)"))
        #expect(!result.user.contains("отклонённый"))
    }

    @Test func substitutesStructure() {
        let t = StageTemplate(stage: .draft, userPromptTemplate: "План:\n{{структура}}")
        let topic = Topic(title: "T", articleType: .info)
        topic.structureText = "# H1 Рак простаты\n## Введение\n- о чём раздел"
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(result.user.contains("# H1 Рак простаты"))
        #expect(result.user.contains("## Введение"))
    }

    @Test func emptyStructureLeavesPlaceholderEmpty() {
        let t = StageTemplate(stage: .draft, userPromptTemplate: "План:[{{структура}}]")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(result.user == "План:[]")
    }

    @Test func selectedBlocksAppendedWhenPresent() {
        let t = StageTemplate(stage: .productBlocks, userPromptTemplate: "Текст: {{текущий_текст}}")
        let topic = Topic(title: "T", articleType: .service)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "Базовый текст",
                                           selectedBlocks: ["CTA", "Блок врача"])
        #expect(result.user.contains("CTA"))
        #expect(result.user.contains("Блок врача"))
    }

    @Test func substitutesKnowledgeBase() {
        let t = StageTemplate(stage: .factCheck, userPromptTemplate: "Справочник:\n{{база_знаний}}")
        let topic = Topic(title: "T", articleType: .disease)
        let adv = KnowledgeNode(title: "Преимущество", type: .advantage, content: "Лечение за один визит")
        let doc = KnowledgeNode(title: "Усычкин С.В.", type: .doctor, content: "Стаж 20 лет")
        topic.attachedNodes = [adv, doc]
        let result = PromptBuilder().build(template: t, topic: topic, currentText: "текст")
        #expect(result.user.contains("Лечение за один визит"))
        #expect(result.user.contains("Усычкин С.В.: Стаж 20 лет"))
    }

    @Test func systemComesDirectlyFromRoleContext() {
        let t = StageTemplate(stage: .draft, userPromptTemplate: "{{тема}}")
        let topic = Topic(title: "T", articleType: .info)

        let result = PromptBuilder().build(
            template: t,
            topic: topic,
            currentText: nil,
            roleContext: "Контекст роли"
        )

        #expect(result.system == "Контекст роли")
        #expect(result.user == "T")
    }

    @Test func emptyRoleContextProducesEmptySystem() {
        let t = StageTemplate(stage: .draft, userPromptTemplate: "{{тема}}")
        let topic = Topic(title: "T", articleType: .info)

        let result = PromptBuilder().build(
            template: t,
            topic: topic,
            currentText: nil,
            roleContext: ""
        )

        #expect(result.system == "")
        #expect(result.user == "T")
    }

    @Test func selectedBlockPromptsInjectedViaPlaceholder() {
        let t = StageTemplate(stage: .productBlocks, userPromptTemplate: "Текст: {{текущий_текст}}\nБлоки:\n{{продуктовые_блоки}}")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(
            template: t, topic: topic, currentText: "тело",
            selectedBlocks: ["Промт А", "Промт Б"]
        )
        #expect(result.user.contains("Промт А"))
        #expect(result.user.contains("Промт Б"))
        #expect(!result.user.contains("{{продуктовые_блоки}}"))
        #expect(result.user.contains("Промт А\n\nПромт Б"))
    }

    @Test func knowledgeVariablesInsideBlockPromptSubstituted() {
        let doctor = KnowledgeNode(title: "Врач", type: .doctor, content: "Иванов И.И., онколог")
        let topic = Topic(title: "T", articleType: .info)
        topic.doctor = doctor
        let t = StageTemplate(stage: .productBlocks, userPromptTemplate: "{{продуктовые_блоки}}")
        let result = PromptBuilder().build(
            template: t, topic: topic, currentText: nil,
            selectedBlocks: ["Данные врача: {{врач_данные}}"]
        )
        #expect(result.user.contains("Данные врача: Иванов И.И., онколог"))
    }

    @Test func blocksAppendedWhenNoPlaceholder() {
        let t = StageTemplate(stage: .productBlocks, userPromptTemplate: "Текст: {{текущий_текст}}")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(
            template: t, topic: topic, currentText: "тело",
            selectedBlocks: ["Блок CTA"]
        )
        #expect(result.user.contains("Блок CTA"))
        #expect(result.user.contains("Текст: тело"))
        #expect(result.user.contains("Продуктовые блоки для встраивания:\nБлок CTA"))
    }

    @Test func substitutesForbiddenPhrasesPlaceholder() {
        let t = StageTemplate(stage: .finalReview, userPromptTemplate: "Запрещено:\n{{запрещённые_формулировки}}")
        let topic = Topic(title: "T", articleType: .info)

        let result = PromptBuilder().build(
            template: t, topic: topic, currentText: "текст",
            forbiddenPhrases: "- «плохая фраза» — проблема: звучит плохо; замена: «хорошая фраза»"
        )

        #expect(result.user.contains("«плохая фраза»"))
    }

    @Test func emptyForbiddenPhrasesFallsBackToStub() {
        let t = StageTemplate(stage: .finalReview, userPromptTemplate: "Запрещено:\n{{запрещённые_формулировки}}")
        let topic = Topic(title: "T", articleType: .info)

        let result = PromptBuilder().build(template: t, topic: topic, currentText: "текст")

        #expect(result.user.contains("(список пуст)"))
    }

    @Test func seoMetaVariablesSubstitutedFromCurrentVersion() {
        let t = StageTemplate(stage: .seoCheck, userPromptTemplate: "H1: {{текущий_h1}}\nTitle: {{текущий_title}}\nDescription: {{текущий_description}}")
        let topic = Topic(title: "T", articleType: .info)
        let version = ArticleVersion(stage: .semanticsInText, source: .generated, text: "тело")
        version.h1 = "Лечение рака простаты"
        version.seoTitle = "Рак простаты — лечение | Клиника"
        version.seoDescription = "Современное лечение рака простаты."
        version.topic = topic
        topic.versions = [version]
        topic.currentVersionID = version.uuid

        let result = PromptBuilder().build(template: t, topic: topic, currentText: "тело")

        #expect(result.user.contains("H1: Лечение рака простаты"))
        #expect(result.user.contains("Title: Рак простаты — лечение | Клиника"))
        #expect(result.user.contains("Description: Современное лечение рака простаты."))
    }

    @Test func seoMetaVariablesEmptyWithoutCurrentVersion() {
        let t = StageTemplate(stage: .seoCheck, userPromptTemplate: "H1:[{{текущий_h1}}]")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(result.user == "H1:[]")
    }

    @Test func emptyPlaceholderRemovedWhenNoBlocks() {
        let t = StageTemplate(stage: .productBlocks, userPromptTemplate: "A {{продуктовые_блоки}} B")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(!result.user.contains("{{продуктовые_блоки}}"))
    }

    @Test func substitutesReaderIntentVariable() {
        let template = StageTemplate(stage: .draft, userPromptTemplate: "{{задача_читателя}}")
        let topic = Topic(title: "Тема", articleType: .info)
        topic.readerIntent = ReaderIntent(query: "запрос", hiddenGoal: "решить задачу")
        let result = PromptBuilder().build(template: template, topic: topic, currentText: nil)
        #expect(result.user.contains("Практическая задача: решить задачу"))
    }

    @Test func missingReaderIntentUsesExplicitFallback() {
        let template = StageTemplate(stage: .structure, userPromptTemplate: "{{задача_читателя}}")
        let topic = Topic(title: "Тема", articleType: .info)
        let result = PromptBuilder().build(template: template, topic: topic, currentText: nil)
        #expect(result.user == "Карта задачи читателя не заполнена.")
    }

    @Test func unrelatedStageDoesNotReceiveReaderIntentEvenWithManualToken() {
        let template = StageTemplate(stage: .factCheck, userPromptTemplate: "До {{задача_читателя}} После")
        let topic = Topic(title: "Тема", articleType: .info)
        topic.readerIntent = ReaderIntent(query: "запрос", hiddenGoal: "решить задачу")
        let result = PromptBuilder().build(template: template, topic: topic, currentText: "Текст")
        #expect(result.user == "До  После")
    }
}
