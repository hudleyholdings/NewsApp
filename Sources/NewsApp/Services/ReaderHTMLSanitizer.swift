import Foundation
import SwiftSoup

enum ReaderHTMLSanitizer {
    private static let mediaSelector = """
    img, picture, source, figure, object, embed, video, audio, canvas, iframe, svg,
    noscript, template, meta, link
    """

    static func sanitizeFragment(_ html: String) -> String {
        let withoutObjectPlaceholders = removeObjectPlaceholders(from: html)

        do {
            let document = try SwiftSoup.parseBodyFragment(withoutObjectPlaceholders)
            try document.select(mediaSelector).remove()
            try document.select("script, style").remove()
            try document.select("[aria-hidden=true]").remove()
            try document.select("[hidden]").remove()
            let sanitized = try document.body()?.html() ?? ""
            return removeObjectPlaceholders(from: sanitized).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return fallbackSanitize(withoutObjectPlaceholders)
        }
    }

    private static func removeObjectPlaceholders(from html: String) -> String {
        html
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "&#65532;", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "&#xfffc;", with: "", options: .caseInsensitive)
    }

    private static func fallbackSanitize(_ html: String) -> String {
        var output = html
        output = output.replacingOccurrences(
            of: #"(?is)<(picture|figure|object|embed|video|audio|canvas|iframe|svg|noscript|template|script|style)\b[^>]*>.*?</\1>"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?is)<(img|source|meta|link)\b[^>]*>"#,
            with: "",
            options: .regularExpression
        )
        return removeObjectPlaceholders(from: output).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
