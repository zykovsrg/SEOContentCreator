import Foundation
import SwiftData

@Model
final class PublishedSitePage {
    var uuid: UUID
    var url: String
    var title: String
    var metaDescription: String
    var h1: [String]
    var h2: [String]
    var siteHost: String
    var indexedAt: Date

    init(
        url: String,
        title: String = "",
        metaDescription: String = "",
        h1: [String] = [],
        h2: [String] = [],
        siteHost: String = "hadassah.moscow",
        indexedAt: Date = .now
    ) {
        self.uuid = UUID()
        self.url = url
        self.title = title
        self.metaDescription = metaDescription
        self.h1 = h1
        self.h2 = h2
        self.siteHost = siteHost
        self.indexedAt = indexedAt
    }

    var summaryForAgent: String {
        var lines = ["URL: \(url)"]

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            lines.append("Title: \(trimmedTitle)")
        }

        let trimmedDescription = metaDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            lines.append("Description: \(trimmedDescription)")
        }

        if !h1.isEmpty {
            lines.append("H1: \(h1.joined(separator: " | "))")
        }

        if !h2.isEmpty {
            lines.append("H2: \(h2.joined(separator: " | "))")
        }

        return lines.joined(separator: "\n")
    }
}
