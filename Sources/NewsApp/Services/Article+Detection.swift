import Foundation

// MARK: - YouTube detection

extension Article {
    /// True when this article is a YouTube video page link. Used by the reader to
    /// render an inline embedded player instead of trying to scrape youtube.com.
    var isYouTubeArticle: Bool { youTubeVideoID != nil }

    /// The 11-character video ID parsed from any YouTube URL form we know about:
    ///   - youtube.com/watch?v=ID
    ///   - youtube.com/v/ID
    ///   - youtube.com/embed/ID
    ///   - youtube.com/shorts/ID
    ///   - youtu.be/ID
    var youTubeVideoID: String? {
        guard let url = link, let host = url.host?.lowercased() else { return nil }
        let path = url.path

        if host == "youtu.be" || host == "www.youtu.be" {
            let id = String(path.drop(while: { $0 == "/" }))
            return YouTubeIDValidator.canonical(id)
        }

        guard host.hasSuffix("youtube.com") else { return nil }

        if path == "/watch" || path.hasPrefix("/watch") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return YouTubeIDValidator.canonical(v)
            }
            return nil
        }
        for prefix in ["/embed/", "/v/", "/shorts/"] {
            if path.hasPrefix(prefix) {
                let id = String(path.dropFirst(prefix.count)).split(separator: "/").first.map(String.init) ?? ""
                return YouTubeIDValidator.canonical(id)
            }
        }
        return nil
    }
}

private enum YouTubeIDValidator {
    /// Real YouTube video IDs are 11 chars of `[A-Za-z0-9_-]`. Reject anything else so
    /// we don't try to embed garbage as if it were a video.
    static func canonical(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 11 else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return trimmed.unicodeScalars.allSatisfy(allowed.contains) ? trimmed : nil
    }
}

// MARK: - Reddit detection

extension Article {
    /// True when this article's link points to a reddit.com post. Used by the reader
    /// to render the post's image + a clean "by /u/X • view comments" footer rather
    /// than dumping the raw `<table>` markup with `[link]` and `[comments]` literals.
    var isRedditArticle: Bool {
        guard let host = link?.host?.lowercased() else { return false }
        return host == "reddit.com"
            || host.hasSuffix(".reddit.com")
            || host == "redd.it"
    }

    /// Parsed metadata from the post's RSS HTML body. Reddit's RSS items embed a
    /// small table with the thumbnail, the submitter, and `[link]` / `[comments]`
    /// anchors — we extract those bits and present them as proper UI.
    var redditMetadata: RedditPostMetadata? {
        guard isRedditArticle else { return nil }
        return RedditPostMetadata.parse(
            contentHTML: contentHTML,
            articleLink: link,
            author: author,
            fallbackImage: imageURL
        )
    }
}

struct RedditPostMetadata {
    let thumbnailURL: URL?
    /// The full-size media or external URL the post points at (the `[link]` anchor).
    let externalLinkURL: URL?
    /// URL of the post's comment thread (the `[comments]` anchor).
    let commentsURL: URL?
    /// Submitter username, e.g. "File_Puzzled" — already stripped of the "/u/" prefix.
    let submitterUsername: String?
    let subreddit: String?
    /// Body text once the boilerplate footer is stripped. Nil when there's nothing
    /// useful left (i.e. link posts with no self-text).
    let cleanedBodyHTML: String?

    static func parse(contentHTML: String?, articleLink: URL?, author: String?, fallbackImage: URL?) -> RedditPostMetadata {
        var thumbnail: URL? = fallbackImage
        var externalLink: URL?
        var comments: URL?
        var submitter: String?
        var subreddit: String?

        if let articleLink {
            let path = articleLink.path
            let parts = path.split(separator: "/")
            if let rIndex = parts.firstIndex(of: "r"), rIndex + 1 < parts.count {
                subreddit = String(parts[rIndex + 1])
            }
        }

        if let html = contentHTML, !html.isEmpty {
            // <img src="…">
            if thumbnail == nil, let imgURL = firstMatch(in: html, pattern: #"<img[^>]*\bsrc=["']([^"']+)["']"#) {
                thumbnail = URL(string: imgURL)
            }
            // /u/USERNAME (anchor text)
            if let user = firstMatch(in: html, pattern: #"/u/([A-Za-z0-9_-]+)"#) {
                submitter = user
            }
            // anchors whose visible text is [link] or [comments]
            externalLink = anchorURL(in: html, withVisibleText: "link")
            comments = anchorURL(in: html, withVisibleText: "comments")
        }

        if submitter == nil, let author { submitter = author.replacingOccurrences(of: "/u/", with: "") }

        // Try to clean the body: strip the `<table>...</table>` boilerplate plus any
        // trailing "submitted by …" sentence. If what remains is empty, return nil so
        // the view shows nothing rather than a hairline of whitespace.
        let cleanedHTML = stripBoilerplate(contentHTML)

        return RedditPostMetadata(
            thumbnailURL: thumbnail,
            externalLinkURL: externalLink ?? articleLink,
            commentsURL: comments ?? articleLink,
            submitterUsername: submitter,
            subreddit: subreddit,
            cleanedBodyHTML: cleanedHTML
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }

    private static func anchorURL(in html: String, withVisibleText label: String) -> URL? {
        let pattern = #"<a[^>]*\bhref=["']([^"']+)["'][^>]*>\s*\[\#(label)\]\s*</a>"#
            .replacingOccurrences(of: "\\#(label)", with: label)
        if let href = firstMatch(in: html, pattern: pattern), let url = URL(string: href) {
            return url
        }
        return nil
    }

    private static func stripBoilerplate(_ html: String?) -> String? {
        guard var working = html, !working.isEmpty else { return nil }
        // Drop the wrapping table that holds the thumbnail + footer anchors.
        working = working.replacingOccurrences(
            of: #"<table[\s\S]*?</table>"#,
            with: "",
            options: .regularExpression
        )
        // Drop the trailing "submitted by … [link] [comments]" sentence if it lived
        // outside the table.
        working = working.replacingOccurrences(
            of: #"submitted by[\s\S]*?\[comments\]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let trimmed = working.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
