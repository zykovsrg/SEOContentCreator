import Foundation

struct SitePageHTMLSummary: Equatable {
    var title: String
    var metaDescription: String
    var h1: [String]
    var h2: [String]
}

enum SitePageHTMLParser {
    static func parse(html: String) -> SitePageHTMLSummary {
        SitePageHTMLSummary(
            title: firstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#),
            metaDescription: metaDescription(in: html),
            h1: allMatches(in: html, pattern: #"<h1[^>]*>(.*?)</h1>"#),
            h2: allMatches(in: html, pattern: #"<h2[^>]*>(.*?)</h2>"#)
        )
    }

    private static func metaDescription(in html: String) -> String {
        let pattern = #"<meta\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ""
        }

        let nsHTML = html as NSString
        var ogDescription = ""

        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let tag = nsHTML.substring(with: match.range)
            let attributes = attributes(in: tag)
            let name = attributes["name"]?.lowercased()
            let property = attributes["property"]?.lowercased()
            let content = clean(attributes["content"] ?? "")

            if name == "description" {
                return content
            }

            if property == "og:description", !content.isEmpty, ogDescription.isEmpty {
                ogDescription = content
            }
        }

        return ogDescription
    }

    private static func firstMatch(in text: String, pattern: String) -> String {
        allMatches(in: text, pattern: pattern).first ?? ""
    }

    private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return clean(nsText.substring(with: match.range(at: 1)))
        }
        .filter { !$0.isEmpty }
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][A-Za-z0-9_:\-\.]*)\s*=\s*(['"])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [:]
        }

        let nsTag = tag as NSString
        var result: [String: String] = [:]

        for match in regex.matches(in: tag, range: NSRange(location: 0, length: nsTag.length)) {
            guard match.numberOfRanges == 4 else { continue }
            let key = nsTag.substring(with: match.range(at: 1)).lowercased()
            let value = nsTag.substring(with: match.range(at: 3))
            result[key] = value
        }

        return result
    }

    private static func clean(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let decoded = decodeHTMLEntities(in: withoutTags)
        return decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(in text: String) -> String {
        let namedDecoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&laquo;", with: "\"")
            .replacingOccurrences(of: "&raquo;", with: "\"")
            .replacingOccurrences(of: "&ndash;", with: "-")
            .replacingOccurrences(of: "&mdash;", with: "-")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        return decodeNumericHTMLEntities(in: namedDecoded)
    }

    private static func decodeNumericHTMLEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let entityBody = nsText.substring(with: match.range(at: 1))
            let scalarValue: UInt32?

            if entityBody.lowercased().hasPrefix("x") {
                scalarValue = UInt32(entityBody.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(entityBody, radix: 10)
            }

            guard
                let value = scalarValue,
                let scalar = UnicodeScalar(value)
            else {
                continue
            }

            let replacement = String(scalar)
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }

        return result
    }
}
