import Testing
@testable import SEOContentCreator

struct SitePageHTMLParserTests {
    @Test func extractsTitleDescriptionAndHeadings() {
        let html = """
        <html><head>
        <title>Лечение рака простаты</title>
        <meta name="description" content="Описание страницы">
        </head><body>
        <h1>Рак простаты</h1>
        <h2>Диагностика</h2>
        <h2>Лечение</h2>
        </body></html>
        """

        let parsed = SitePageHTMLParser.parse(html: html)

        #expect(parsed.title == "Лечение рака простаты")
        #expect(parsed.metaDescription == "Описание страницы")
        #expect(parsed.h1 == ["Рак простаты"])
        #expect(parsed.h2 == ["Диагностика", "Лечение"])
    }

    @Test func stripsNestedTagsAndCommonHTMLEntities() {
        let html = """
        <html><head>
        <title>Клиника &amp; лечение</title>
        <meta content="Описание&nbsp;страницы" name="description">
        </head><body>
        <h1><span>Рак</span> простаты</h1>
        <h2>Первый <strong>раздел</strong></h2>
        </body></html>
        """

        let parsed = SitePageHTMLParser.parse(html: html)

        #expect(parsed.title == "Клиника & лечение")
        #expect(parsed.metaDescription == "Описание страницы")
        #expect(parsed.h1 == ["Рак простаты"])
        #expect(parsed.h2 == ["Первый раздел"])
    }

    @Test func fallsBackToOGDescriptionWhenStandardDescriptionIsMissing() {
        let html = """
        <html><head>
        <meta property="og:description" content="Описание из og">
        </head><body></body></html>
        """

        let parsed = SitePageHTMLParser.parse(html: html)

        #expect(parsed.metaDescription == "Описание из og")
    }

    @Test func prefersStandardDescriptionOverOGDescription() {
        let html = """
        <html><head>
        <meta property="og:description" content="Описание из og">
        <meta name="description" content="Основное описание">
        </head><body></body></html>
        """

        let parsed = SitePageHTMLParser.parse(html: html)

        #expect(parsed.metaDescription == "Основное описание")
    }

    @Test func ignoresPropertyDescriptionWithoutOGPrefix() {
        let html = """
        <html><head>
        <meta property="description" content="Неверное описание">
        </head><body></body></html>
        """

        let parsed = SitePageHTMLParser.parse(html: html)

        #expect(parsed.metaDescription.isEmpty)
    }

    @Test func decodesNumericAndTypographyEntities() {
        let html = """
        <html><head>
        <title>&laquo;Клиника&raquo; &#39;Hadassah&#39; &#x27;Moscow&#x27; &ndash; &mdash;</title>
        <meta name="description" content="&#39;Описание&#39; &laquo;страницы&raquo;">
        </head><body>
        <h1>&laquo;Рак&#39; простаты&raquo;</h1>
        </body></html>
        """

        let parsed = SitePageHTMLParser.parse(html: html)

        #expect(parsed.title == "\"Клиника\" 'Hadassah' 'Moscow' - -")
        #expect(parsed.metaDescription == "'Описание' \"страницы\"")
        #expect(parsed.h1 == ["\"Рак' простаты\""])
    }

    @Test func parsesSingleQuotedAttributes() {
        let html = """
        <html><head>
        <meta name='description' content='Описание в одинарных кавычках'>
        </head><body>
        <h2>Раздел</h2>
        </body></html>
        """

        let parsed = SitePageHTMLParser.parse(html: html)

        #expect(parsed.metaDescription == "Описание в одинарных кавычках")
        #expect(parsed.h2 == ["Раздел"])
    }
}
