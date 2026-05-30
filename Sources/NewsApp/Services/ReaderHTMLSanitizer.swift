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

            // Collapse blocks that used to host the media we just removed. Without
            // this, an audio embed wrapped in <figure><iframe/></figure> leaves an
            // empty <figure> behind that still pads vertical space, producing the
            // large blank gap users see between "Listen to this post:" and the
            // article body.
            try removeEmptyBlocks(in: document)

            let sanitized = try document.body()?.html() ?? ""
            return removeObjectPlaceholders(from: sanitized).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return fallbackSanitize(withoutObjectPlaceholders)
        }
    }

    /// Iteratively remove `<p>`, `<div>`, `<section>`, `<figure>`, and `<aside>`
    /// nodes whose visible text and remaining children are empty (or just `<br>`).
    /// Two passes: the first wipes the most-deeply-nested empties, the second
    /// catches parents that became empty as a result.
    private static func removeEmptyBlocks(in document: SwiftSoup.Document) throws {
        let blockSelector = "p, div, section, figure, aside, blockquote"
        for _ in 0..<3 {
            let candidates = try document.select(blockSelector)
            var removedAny = false
            for node in candidates {
                let text = (try? node.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard text.isEmpty else { continue }
                // Keep blocks that still have non-br element children (e.g. nested
                // div with an image we want to preserve).
                let nonBrChildren = node.children().filter { $0.tagName().lowercased() != "br" }
                guard nonBrChildren.isEmpty else { continue }
                try? node.remove()
                removedAny = true
            }
            if !removedAny { break }
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
