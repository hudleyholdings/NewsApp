import Foundation

struct FeedFetchResult {
    var parseResult: FeedParseResult?
    var httpStatus: Int
    var etag: String?
    var lastModified: String?
    var notModified: Bool
}

final class FeedFetcher: @unchecked Sendable {
    private let parser = FeedParser()

    func fetchFeed(from url: URL, etag: String?, lastModified: String?) async throws -> FeedFetchResult {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20
        request.setValue("NewsApp/1.0 (macOS; RSS Reader)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/feed+json, text/xml, application/xml;q=0.9, application/json;q=0.8, */*;q=0.5", forHTTPHeaderField: "Accept")
        if let etag = etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let status = http.statusCode
        if status == 304 {
            return FeedFetchResult(parseResult: nil, httpStatus: status, etag: http.value(forHTTPHeaderField: "ETag"), lastModified: http.value(forHTTPHeaderField: "Last-Modified"), notModified: true)
        }

        guard (200...299).contains(status) else {
            throw URLError(.badServerResponse)
        }

        let parsed = try parser.parse(data: data, url: url)
        return FeedFetchResult(parseResult: parsed, httpStatus: status, etag: http.value(forHTTPHeaderField: "ETag"), lastModified: http.value(forHTTPHeaderField: "Last-Modified"), notModified: false)
    }
}
