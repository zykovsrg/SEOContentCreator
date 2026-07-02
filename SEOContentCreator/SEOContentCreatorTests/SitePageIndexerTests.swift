import Foundation
import Testing
@testable import SEOContentCreator

struct SitePageIndexerTests {
    @Test func extractsSitemapLocations() throws {
        let xml = """
        <urlset>
          <url><loc>https://hadassah.moscow/a</loc></url>
          <url><loc>https://hadassah.moscow/b</loc></url>
        </urlset>
        """

        let urls = SitePageIndexer.extractURLs(fromSitemapXML: xml)

        #expect(urls.map(\.absoluteString) == [
            "https://hadassah.moscow/a",
            "https://hadassah.moscow/b"
        ])
    }

    @Test func keepsOnlyHadassahHTMLURLs() {
        let urls = [
            URL(string: "https://hadassah.moscow/a")!,
            URL(string: "https://example.com/b")!,
            URL(string: "https://hadassah.moscow/file.pdf")!,
            URL(string: "https://hadassah.moscow/image.webp")!
        ]

        let filtered = SitePageIndexer.filterPageURLs(urls)

        #expect(filtered.map(\.absoluteString) == ["https://hadassah.moscow/a"])
    }
}
