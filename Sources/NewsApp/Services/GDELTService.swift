import Foundation

enum GDELTServiceError: Error {
    case invalidQuery
    case invalidResponse
}

struct GDELTArticle: Decodable {
    let url: String
    let url_mobile: String?
    let title: String
    let seendate: String?
    let socialimage: String?
    let domain: String?
    let language: String?
    let sourcecountry: String?
}

struct GDELTResponse: Decodable {
    let articles: [GDELTArticle]
}

final class GDELTService: @unchecked Sendable {
    private let logger = AppLogger.shared

    func fetchEntries(config: GDELTSourceConfig) async throws -> [FeedEntry] {
        let url = try buildURL(config: config)
        let timer = logger.begin("gdelt.fetch")
        logger.log("GDELT fetch start url=\(url.absoluteString)")
        defer { timer.end() }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("NewsApp/1.0 (macOS; RSS Reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            logger.error("GDELT fetch bad status url=\(url.absoluteString)")
            throw GDELTServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(GDELTResponse.self, from: data)
        let entries = entries(from: decoded)
        logger.log("GDELT fetch ok count=\(entries.count)")
        return entries
    }

    func buildURL(config: GDELTSourceConfig) throws -> URL {
        guard let query = buildQuery(config: config), !query.isEmpty else {
            throw GDELTServiceError.invalidQuery
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.gdeltproject.org"
        components.path = "/api/v2/doc/doc"
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "mode", value: "ArtList"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "maxrecords", value: String(max(1, min(250, config.maxRecords)))),
            URLQueryItem(name: "timespan", value: timespanValue(for: config.timeWindow))
        ]

        guard let url = components.url else {
            throw GDELTServiceError.invalidQuery
        }
        return url
    }

    func sourceURL(config: GDELTSourceConfig) -> URL? {
        try? buildURL(config: config)
    }

    func buildQuery(config: GDELTSourceConfig) -> String? {
        var terms: [String] = []
        if let topic = config.topic {
            terms.append(topic.query)
        }
        if !config.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            terms.append(config.query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let language = config.language.code {
            terms.append("sourcelang:\(language)")
        }
        if let country = normalizedCountry(config.country) {
            terms.append("sourcecountry:\(country)")
        }
        if let domain = normalizedDomain(config.domain) {
            terms.append("domain:\(domain)")
        }
        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: " ")
    }

    func entries(from response: GDELTResponse) -> [FeedEntry] {
        response.articles.compactMap { article -> FeedEntry? in
            guard !article.url.isEmpty else { return nil }
            let publishedAt = article.seendate.flatMap { GDELTService.parseDate($0) }
            return FeedEntry(
                externalID: article.url,
                title: article.title,
                link: article.url,
                summary: nil,
                contentHTML: nil,
                author: article.domain ?? article.sourcecountry,
                publishedAt: publishedAt,
                imageURL: article.socialimage
            )
        }
    }

    private func timespanValue(for window: GDELTTimeWindow) -> String {
        let hours = window.hours
        if hours % 24 == 0 {
            return "\(hours / 24)d"
        }
        return "\(hours)h"
    }

    private func normalizedCountry(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }

    private func normalizedDomain(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private static func parseDate(_ value: String) -> Date? {
        return GDELTService.dateFormatter.date(from: value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
