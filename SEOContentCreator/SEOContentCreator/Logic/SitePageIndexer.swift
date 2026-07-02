import Foundation

struct SitePageIndexer {
    enum IndexerError: Error, LocalizedError {
        case sitemapUnavailable

        var errorDescription: String? {
            switch self {
            case .sitemapUnavailable:
                return "Не удалось получить sitemap сайта."
            }
        }
    }

    let session: URLSession
    let sitemapURL: URL

    init(
        session: URLSession = .shared,
        sitemapURL: URL = URL(string: "https://hadassah.moscow/sitemap.xml")!
    ) {
        self.session = session
        self.sitemapURL = sitemapURL
    }

    static func extractURLs(fromSitemapXML xml: String) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<loc>(.*?)</loc>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: raw)
        }
    }

    static func filterPageURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            guard url.host == "hadassah.moscow" else { return false }

            let path = url.path.lowercased()
            return ![
                ".pdf",
                ".jpg",
                ".jpeg",
                ".png",
                ".webp",
                ".gif",
                ".svg"
            ].contains { path.hasSuffix($0) }
        }
    }

    func fetchPages(limit: Int = 200) async throws -> [PublishedSitePage] {
        let (sitemapData, response) = try await session.data(from: sitemapURL)
        guard let http = response as? HTTPURLResponse,
              200...299 ~= http.statusCode,
              let xml = String(data: sitemapData, encoding: .utf8) else {
            throw IndexerError.sitemapUnavailable
        }

        let urls = Self.filterPageURLs(Self.extractURLs(fromSitemapXML: xml)).prefix(limit)
        var pages: [PublishedSitePage] = []

        for url in urls {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      200...299 ~= http.statusCode,
                      let html = String(data: data, encoding: .utf8) else {
                    continue
                }

                let summary = SitePageHTMLParser.parse(html: html)
                pages.append(PublishedSitePage(
                    url: url.absoluteString,
                    title: summary.title,
                    metaDescription: summary.metaDescription,
                    h1: summary.h1,
                    h2: summary.h2
                ))
            } catch {
                continue
            }
        }

        return pages
    }
}
