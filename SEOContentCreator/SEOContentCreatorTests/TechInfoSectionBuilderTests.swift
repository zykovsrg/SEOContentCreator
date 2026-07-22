import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

struct TechInfoSectionBuilderTests {

    @Test func sectionPathMapsArticleTypes() {
        #expect(TechInfoSectionBuilder.sectionPath(for: .disease) == "/deseases/")
        #expect(TechInfoSectionBuilder.sectionPath(for: .service) == "/services/")
        #expect(TechInfoSectionBuilder.sectionPath(for: .info) == "/article/")
    }

    @Test func buildFillsAllKnownFields() {
        let section = TechInfoSectionBuilder.build(
            seoTitle: "Лечение цистита", seoDescription: "Описание страницы",
            expert: "Иванова А. А.", directions: ["Урология", "Андрология"],
            articleType: .service)
        #expect(section.hasPrefix("## Техническая информация"))
        #expect(section.contains("Тайтл: Лечение цистита"))
        #expect(section.contains("Дескрипшн: Описание страницы"))
        #expect(section.contains("Эксперт: Иванова А. А."))
        #expect(section.contains("Врачи отделения: [вписать вручную]"))
        #expect(section.contains("Направления: Урология, Андрология"))
        #expect(section.contains("Раздел: /services/"))
        #expect(section.contains("URL: [вписать вручную]"))
        #expect(section.contains("Иллюстрации: [появится при публикации]"))
    }

    @Test func buildFallsBackToManualPlaceholders() {
        let section = TechInfoSectionBuilder.build(
            seoTitle: nil, seoDescription: "  ", expert: nil,
            directions: [], articleType: .disease)
        #expect(section.contains("Тайтл: [вписать вручную]"))
        #expect(section.contains("Дескрипшн: [вписать вручную]"))
        #expect(section.contains("Эксперт: [вписать вручную]"))
        #expect(section.contains("Направления: [вписать вручную]"))
    }

    @Test func appendAddsSectionOnce() {
        let section = TechInfoSectionBuilder.build(
            seoTitle: "T", seoDescription: "D", expert: nil,
            directions: [], articleType: .info)
        let once = TechInfoSectionBuilder.append(to: "# Статья\n\nТекст.", section: section)
        #expect(once.hasSuffix(section))
        #expect(once.contains("# Статья"))
        let twice = TechInfoSectionBuilder.append(to: once, section: section)
        #expect(twice == once)  // idempotent
    }

    @Test func substituteReplacesIllustrationsPlaceholder() {
        let text = "Текст\n\n## Техническая информация\n\nИллюстрации: [появится при публикации]"
        let out = TechInfoSectionBuilder.substituteIllustrationsLink(
            in: text, url: "https://drive.google.com/drive/folders/abc")
        #expect(out.contains("Иллюстрации: https://drive.google.com/drive/folders/abc"))
        #expect(!out.contains("[появится при публикации]"))
        // No placeholder → text unchanged.
        #expect(TechInfoSectionBuilder.substituteIllustrationsLink(in: "чистый текст", url: "u") == "чистый текст")
    }

    @Test @MainActor func sectionForTopicGathersData() throws {
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, KnowledgeNode.self, ArticleVersion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let direction = KnowledgeNode(title: "Урология", type: .direction)
        let extra = KnowledgeNode(title: "Андрология", type: .direction)
        let doctor = KnowledgeNode(title: "Петров П. П.", type: .doctor)
        ctx.insert(direction); ctx.insert(extra); ctx.insert(doctor)
        let topic = Topic(title: "Тема", articleType: .service, direction: direction, doctor: doctor)
        topic.additionalDirections = [extra]
        ctx.insert(topic)
        let v = ArticleVersion(stage: .semanticsInText, source: .generated, text: "Текст")
        v.seoTitle = "SEO тайтл"; v.seoDescription = "SEO дескрипшн"
        v.topic = topic; ctx.insert(v)
        topic.currentVersionID = v.uuid

        let section = TechInfoSectionBuilder.section(for: topic)
        #expect(section.contains("Тайтл: SEO тайтл"))
        #expect(section.contains("Дескрипшн: SEO дескрипшн"))
        #expect(section.contains("Эксперт: Петров П. П."))
        #expect(section.contains("Направления: Урология, Андрология"))
        #expect(section.contains("Раздел: /services/"))
    }

    @Test @MainActor func sectionForTopicFallsBackToLatestSEOFields() throws {
        // checkApplied versions don't carry seoTitle; the builder must look back
        // through older versions for the newest non-empty values.
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, KnowledgeNode.self, ArticleVersion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        ctx.insert(topic)
        let old = ArticleVersion(stage: .semanticsInText, source: .generated, text: "Старый")
        old.seoTitle = "Тайтл из семантики"; old.topic = topic; ctx.insert(old)
        let current = ArticleVersion(stage: .factCheck, source: .checkApplied, text: "Новый")
        current.topic = topic; ctx.insert(current)
        topic.currentVersionID = current.uuid

        let section = TechInfoSectionBuilder.section(for: topic)
        #expect(section.contains("Тайтл: Тайтл из семантики"))
    }
}
