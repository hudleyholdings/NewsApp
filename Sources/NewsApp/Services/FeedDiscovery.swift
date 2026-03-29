import Foundation
import SwiftSoup

struct DiscoveredFeed: Hashable {
    var title: String
    var url: URL
}

final class FeedDiscovery: @unchecked Sendable {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    func discover(from input: String) async throws -> (siteURL: URL, feeds: [DiscoveredFeed]) {
        let normalizedURL = normalizeInput(input)

        // First, check if the input URL itself is a valid feed
        if let feed = await verifyFeed(url: normalizedURL) {
            return (normalizedURL, [feed])
        }

        // Fetch the page and look for autodiscovery links
        var feeds: [DiscoveredFeed] = []

        if let html = try? await fetchHTML(url: normalizedURL),
           let document = try? SwiftSoup.parse(html) {

            // Look for standard autodiscovery links
            if let linkElements = try? document.select("link[rel=alternate]") {
                for link in linkElements.array() {
                    let type = (try? link.attr("type")) ?? ""
                    let href = (try? link.attr("href")) ?? ""
                    if type.contains("rss") || type.contains("atom") || type.contains("json") || type.contains("xml") {
                        if let absoluteURL = URL(string: href, relativeTo: normalizedURL)?.absoluteURL {
                            let title = (try? link.attr("title")) ?? absoluteURL.lastPathComponent
                            feeds.append(DiscoveredFeed(title: title, url: absoluteURL))
                        }
                    }
                }
            }

            // Also look for links with rel="feed" (less common but valid)
            if let feedLinks = try? document.select("link[rel=feed]") {
                for link in feedLinks.array() {
                    let href = (try? link.attr("href")) ?? ""
                    if let absoluteURL = URL(string: href, relativeTo: normalizedURL)?.absoluteURL {
                        let title = (try? link.attr("title")) ?? "Feed"
                        if !feeds.contains(where: { $0.url == absoluteURL }) {
                            feeds.append(DiscoveredFeed(title: title, url: absoluteURL))
                        }
                    }
                }
            }

            // Look for common feed links in the page content (a tags with feed URLs)
            if let anchors = try? document.select("a[href*=feed], a[href*=rss], a[href*=atom], a[href$=.xml]") {
                for anchor in anchors.array().prefix(5) { // Limit to avoid too many
                    let href = (try? anchor.attr("href")) ?? ""
                    if let absoluteURL = URL(string: href, relativeTo: normalizedURL)?.absoluteURL,
                       isLikelyFeedURL(absoluteURL),
                       !feeds.contains(where: { $0.url == absoluteURL }) {
                        let title = (try? anchor.text()) ?? absoluteURL.lastPathComponent
                        feeds.append(DiscoveredFeed(title: title.isEmpty ? "Feed" : title, url: absoluteURL))
                    }
                }
            }
        }

        // If no feeds found via autodiscovery, probe common fallback URLs
        if feeds.isEmpty {
            feeds = await probeCommonFeedURLs(for: normalizedURL)
        }

        // Verify discovered feeds actually work (in parallel, with limit)
        if !feeds.isEmpty {
            feeds = await verifyFeeds(feeds, limit: 8)
        }

        return (normalizedURL, feeds)
    }

    // MARK: - URL Normalization

    private func normalizeInput(_ input: String) -> URL {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove trailing slashes for consistency
        while cleaned.hasSuffix("/") && cleaned.count > 1 {
            cleaned.removeLast()
        }

        if let url = URL(string: cleaned), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(cleaned)") ?? URL(string: "https://example.com")!
    }

    // MARK: - Feed Detection

    private func isLikelyFeedURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        let feedIndicators = ["rss", "atom", "feed", "xml", "json"]
        return feedIndicators.contains { lower.contains($0) }
    }

    private func verifyFeed(url: URL) async -> DiscoveredFeed? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/xml, application/json, text/xml, */*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            // Check content type
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let isFeedContentType = contentType.contains("xml") ||
                                    contentType.contains("rss") ||
                                    contentType.contains("atom") ||
                                    contentType.contains("json")

            // Check content body for feed signatures
            let preview = String(decoding: data.prefix(1000), as: UTF8.self).lowercased()
            let isFeedContent = preview.contains("<rss") ||
                               preview.contains("<feed") ||
                               preview.contains("<rdf:rdf") ||
                               preview.contains("\"version\"") ||  // JSON Feed
                               preview.contains("<?xml") && (preview.contains("<channel") || preview.contains("<entry"))

            if isFeedContentType || isFeedContent {
                // Extract title from feed if possible
                let title = extractFeedTitle(from: data) ?? url.host ?? "Feed"
                return DiscoveredFeed(title: title, url: url)
            }
        } catch {
            // URL doesn't work or isn't a feed
        }

        return nil
    }

    private func verifyFeeds(_ feeds: [DiscoveredFeed], limit: Int) async -> [DiscoveredFeed] {
        let feedsToCheck = Array(feeds.prefix(limit))

        return await withTaskGroup(of: DiscoveredFeed?.self) { group in
            for feed in feedsToCheck {
                group.addTask {
                    await self.verifyFeed(url: feed.url)
                }
            }

            var verified: [DiscoveredFeed] = []
            for await result in group {
                if let feed = result {
                    verified.append(feed)
                }
            }
            return verified
        }
    }

    private func extractFeedTitle(from data: Data) -> String? {
        let content = String(decoding: data.prefix(5000), as: UTF8.self)

        // Try to extract <title> from RSS/Atom
        if let range = content.range(of: "<title>"),
           let endRange = content.range(of: "</title>", range: range.upperBound..<content.endIndex) {
            let title = String(content[range.upperBound..<endRange.lowerBound])
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && title.count < 200 {
                return title
            }
        }

        // Try JSON Feed title
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let title = json["title"] as? String {
            return title
        }

        return nil
    }

    // MARK: - Fallback URL Probing

    private func probeCommonFeedURLs(for baseURL: URL) async -> [DiscoveredFeed] {
        // Comprehensive list of common feed URL patterns
        let paths = [
            // Most common
            "/feed",
            "/feed.xml",
            "/rss",
            "/rss.xml",
            "/atom.xml",
            "/index.xml",

            // WordPress patterns
            "/feed/",
            "/feed/rss",
            "/feed/rss2",
            "/feed/atom",
            "/?feed=rss",
            "/?feed=rss2",
            "/?feed=atom",
            "/comments/feed",

            // Blogger/other patterns
            "/feeds/posts/default",
            "/rss/",
            "/atom/",
            "/rss.php",

            // Common alternatives
            "/feed.rss",
            "/feed.atom",
            "/index.rss",
            "/index.atom",
            "/blog/feed",
            "/blog/rss",
            "/blog.xml",
            "/posts.xml",
            "/posts.rss",
            "/articles.xml",
            "/news/feed",
            "/news/rss",
            "/news.xml",

            // Query string patterns
            "?format=rss",
            "?format=atom",
            "?format=feed",
            "?rss=1",
            "?atom=1",

            // Substack/Ghost/etc
            "/rss/",
            "/public/rss",

            // Tumblr
            "/rss",

            // Medium
            "/feed",

            // Jekyll/Hugo/static sites
            "/feed.xml",
            "/index.xml",
            "/sitemap.xml", // Sometimes contains feed info
        ]

        // Remove duplicates while preserving order
        var seen = Set<String>()
        let uniquePaths = paths.filter { seen.insert($0).inserted }

        // Build URLs
        let urls = uniquePaths.compactMap { path -> URL? in
            if path.hasPrefix("?") {
                // Query string - append to base URL
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
                let queryItems = path.dropFirst().split(separator: "=").map { String($0) }
                if queryItems.count == 2 {
                    components?.queryItems = [URLQueryItem(name: queryItems[0], value: queryItems[1])]
                }
                return components?.url
            } else {
                return URL(string: path, relativeTo: baseURL)?.absoluteURL
            }
        }

        // Probe URLs in parallel (limit concurrent requests)
        return await withTaskGroup(of: DiscoveredFeed?.self) { group in
            for url in urls.prefix(20) { // Limit to avoid hammering servers
                group.addTask {
                    await self.verifyFeed(url: url)
                }
            }

            var found: [DiscoveredFeed] = []
            for await result in group {
                if let feed = result {
                    found.append(feed)
                    // Return early once we find a few valid feeds
                    if found.count >= 3 {
                        group.cancelAll()
                        break
                    }
                }
            }
            return found
        }
    }

    // MARK: - HTTP Helpers

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }
}
