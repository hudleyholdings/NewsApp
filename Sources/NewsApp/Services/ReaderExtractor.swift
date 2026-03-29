import Foundation
import SwiftSoup

struct ReaderContent {
    var title: String
    var byline: String?
    var text: String
    var leadImageURL: URL?
    var contentHTML: String?
}

final class ReaderExtractor {
    /// Lightweight extraction of just the og:image URL without full content parsing.
    static func extractOGImage(from html: String, baseURL: URL?) -> URL? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        guard let content = try? document.select("meta[property=og:image]").first()?.attr("content"),
              !content.isEmpty else { return nil }
        return URL(string: content, relativeTo: baseURL)?.absoluteURL
    }

    func extract(from html: String, baseURL: URL?) throws -> ReaderContent {
        let document = try SwiftSoup.parse(html)
        try document.select("script, style, nav, footer, aside, noscript, iframe, form, header").remove()
        try document.select("[role=contentinfo], .advert, .ads, .ad, .promo, .subscribe, .newsletter, .cookie").remove()

        let title = (try? document.select("meta[property=og:title]").first()?.attr("content"))
            ?? (try? document.select("h1").first()?.text())
            ?? (try? document.title())
            ?? "Article"

        let byline = (try? document.select("meta[name=author]").first()?.attr("content"))
            ?? (try? document.select(".byline").first()?.text())

        let leadImage = (try? document.select("meta[property=og:image]").first()?.attr("content"))
        let leadImageURL = leadImage.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }

        let bodyElement = try document.select("article").first()
            ?? document.select("main").first()
            ?? document.body()

        let paragraphElements = (try? bodyElement?.select("p").array()) ?? []
        let paragraphTexts = (try? paragraphElements.compactMap { element -> String? in
            let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }) ?? []
        let paragraphHTML = (try? paragraphElements.compactMap { element -> String? in
            let html = try element.html().trimmingCharacters(in: .whitespacesAndNewlines)
            return html.isEmpty ? nil : html
        }) ?? []

        let text: String
        if paragraphTexts.isEmpty {
            text = (try? bodyElement?.text()) ?? ""
        } else {
            text = paragraphTexts.joined(separator: "\n\n")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = ReaderCleaner.clean(trimmed)

        let contentHTML = paragraphHTML.isEmpty ? nil : paragraphHTML.map { "<p>\($0)</p>" }.joined(separator: "\n")
        return ReaderContent(title: title, byline: byline, text: cleaned, leadImageURL: leadImageURL, contentHTML: contentHTML)
    }
}

enum ReaderCleaner {
    private static let patterns: [String] = [
        "save this story",
        "save the story",
        "leave your feedback",
        "sign in",
        "sign up",
        "create account",
        "subscribe",
        "newsletter",
        "listen to this",
        "watch live",
        "read more",
        "share this",
        "updated:"
    ]
    private static let metaPrefixes = [
        "by ",
        "published",
        "updated",
        "posted",
        "from ",
        "credit:"
    ]

    static func clean(_ text: String) -> String {
        guard UserDefaults.standard.bool(forKey: "readerCleanupEnabled") else { return text }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { return text }

        while let first = paragraphs.first, shouldDropParagraph(first) {
            paragraphs.removeFirst()
        }

        let result = paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result
    }

    private static func shouldDropParagraph(_ paragraph: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count < 120 else { return false }
        let lower = trimmed.lowercased()
        if patterns.contains(where: { lower.contains($0) }) {
            return true
        }
        if metaPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return true
        }
        if containsDateMetadata(lower) {
            return true
        }
        return false
    }

    private static func containsDateMetadata(_ text: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: "\\b\\w+\\s+\\d{1,2},\\s+\\d{4}\\b", options: [.caseInsensitive])
        if let regex = regex, regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }
        if text.contains(":") && (text.contains("am") || text.contains("pm")) {
            return true
        }
        return false
    }
}
