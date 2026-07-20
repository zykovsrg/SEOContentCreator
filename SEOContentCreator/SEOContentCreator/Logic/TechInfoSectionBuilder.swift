import Foundation

/// Builds the «Техническая информация» section that is appended to the end of
/// the article text when the «Финальная вычитка» stage completes, and later
/// updated at publish time (illustrations folder link).
enum TechInfoSectionBuilder {
    static let header = "## Техническая информация"
    static let manualPlaceholder = "[вписать вручную]"
    static let illustrationsPlaceholder = "[появится при публикации]"
    private static let illustrationsLinePrefix = "Иллюстрации: "

    /// Site section path by article type. Paths use the site's own spelling
    /// (including «deseases») — agreed with the user 2026-07-20.
    static func sectionPath(for type: ArticleType) -> String {
        switch type {
        case .disease: return "/deseases/"
        case .service: return "/services/"
        case .info:    return "/article/"
        }
    }

    static func build(seoTitle: String?, seoDescription: String?, expert: String?,
                      directions: [String], articleType: ArticleType) -> String {
        func filled(_ value: String?) -> String {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? manualPlaceholder : trimmed
        }
        let directionsLine = directions.isEmpty ? manualPlaceholder : directions.joined(separator: ", ")
        return """
        \(header)

        Тайтл: \(filled(seoTitle))
        Дескрипшн: \(filled(seoDescription))
        Эксперт: \(filled(expert))
        Врачи отделения: \(manualPlaceholder)
        Направления: \(directionsLine)
        Раздел: \(sectionPath(for: articleType))
        URL: \(manualPlaceholder)
        \(illustrationsLinePrefix)\(illustrationsPlaceholder)
        """
    }

    /// Appends the section unless the text already contains one (idempotent).
    static func append(to text: String, section: String) -> String {
        guard !text.contains(header) else { return text }
        return text + "\n\n" + section
    }

    /// Gathers section data from the topic. SEO title/description come from the
    /// current version, falling back to the newest older version that has them
    /// (checkApplied versions don't carry SEO fields).
    static func section(for topic: Topic) -> String {
        let byDate = topic.versions.sorted { $0.createdAt > $1.createdAt }
        func newest(_ keyPath: KeyPath<ArticleVersion, String?>) -> String? {
            if let value = topic.currentVersion?[keyPath: keyPath],
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            return byDate.compactMap { $0[keyPath: keyPath] }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let directions = ([topic.direction].compactMap { $0 } + topic.additionalDirections).map(\.title)
        return build(
            seoTitle: newest(\.seoTitle),
            seoDescription: newest(\.seoDescription),
            expert: topic.doctor?.title,
            directions: directions,
            articleType: topic.articleType)
    }

    /// Replaces the illustrations placeholder line value with the real folder URL.
    static func substituteIllustrationsLink(in text: String, url: String) -> String {
        text.replacingOccurrences(
            of: illustrationsLinePrefix + illustrationsPlaceholder,
            with: illustrationsLinePrefix + url)
    }
}
