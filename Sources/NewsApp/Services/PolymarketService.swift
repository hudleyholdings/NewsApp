import Foundation

enum PolymarketServiceError: Error {
    case invalidConfig
    case invalidResponse
    case networkError(Error)
    case noData
}

final class PolymarketService: @unchecked Sendable {
    private let logger = AppLogger.shared
    private let gammaBaseURL = "https://gamma-api.polymarket.com"
    private let clobBaseURL = "https://clob.polymarket.com"

    // Shared session with caching
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.urlCache = URLCache(memoryCapacity: 10_000_000, diskCapacity: 50_000_000)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    // MARK: - Gamma API (Market Discovery)

    func fetchEntries(config: PolymarketSourceConfig) async throws -> [FeedEntry] {
        let url = try buildURL(config: config)
        let timer = logger.begin("polymarket.fetch")
        defer { timer.end() }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("NewsApp/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            logger.error("Polymarket fetch bad status url=\(url.absoluteString)")
            throw PolymarketServiceError.invalidResponse
        }

        let events = try JSONDecoder().decode([PolymarketEvent].self, from: data)
        let entries = entries(from: events)
        logger.log("Polymarket fetch ok count=\(entries.count)")
        return entries
    }

    func fetchTrendingEvents(limit: Int = 10) async throws -> [PolymarketEvent] {
        var components = URLComponents(string: "\(gammaBaseURL)/events")!
        components.queryItems = [
            URLQueryItem(name: "active", value: "true"),
            URLQueryItem(name: "closed", value: "false"),
            URLQueryItem(name: "order", value: "volume24hr"),
            URLQueryItem(name: "ascending", value: "false"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw PolymarketServiceError.invalidConfig
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NewsApp/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PolymarketServiceError.invalidResponse
        }

        return try JSONDecoder().decode([PolymarketEvent].self, from: data)
    }

    func buildURL(config: PolymarketSourceConfig) throws -> URL {
        var components = URLComponents(string: "\(gammaBaseURL)/events")!
        var queryItems = [
            URLQueryItem(name: "active", value: "true"),
            URLQueryItem(name: "closed", value: config.showResolved ? "true" : "false"),
            URLQueryItem(name: "order", value: config.sort.orderParam),
            URLQueryItem(name: "ascending", value: config.sort.ascending ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(max(1, min(100, config.maxRecords))))
        ]

        if let tagSlug = config.category.tagSlug {
            queryItems.append(URLQueryItem(name: "tag_slug", value: tagSlug))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw PolymarketServiceError.invalidConfig
        }
        return url
    }

    func sourceURL(config: PolymarketSourceConfig) -> URL? {
        try? buildURL(config: config)
    }

    // MARK: - CLOB API (Real-time Prices & History)

    /// Fetch current price for a token
    func fetchCurrentPrice(tokenID: String) async throws -> Double {
        let url = URL(string: "\(clobBaseURL)/price?token_id=\(tokenID)&side=buy")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PolymarketServiceError.invalidResponse
        }

        struct PriceResponse: Decodable {
            let price: String
        }

        let priceResponse = try JSONDecoder().decode(PriceResponse.self, from: data)
        return Double(priceResponse.price) ?? 0
    }

    /// Fetch midpoint price for a token
    func fetchMidpoint(tokenID: String) async throws -> Double {
        let url = URL(string: "\(clobBaseURL)/midpoint?token_id=\(tokenID)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PolymarketServiceError.invalidResponse
        }

        struct MidpointResponse: Decodable {
            let mid: String
        }

        let midResponse = try JSONDecoder().decode(MidpointResponse.self, from: data)
        return Double(midResponse.mid) ?? 0
    }

    /// Fetch price history for sparklines
    func fetchPriceHistory(tokenID: String, interval: PriceHistoryInterval = .oneWeek) async throws -> [PricePoint] {
        let url = URL(string: "\(clobBaseURL)/prices-history?market=\(tokenID)&interval=\(interval.rawValue)&fidelity=60")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PolymarketServiceError.invalidResponse
        }

        struct HistoryResponse: Decodable {
            let history: [PricePointRaw]
        }

        struct PricePointRaw: Decodable {
            let t: Int // timestamp
            let p: String // price
        }

        let historyResponse = try JSONDecoder().decode(HistoryResponse.self, from: data)
        return historyResponse.history.compactMap { raw in
            guard let price = Double(raw.p) else { return nil }
            return PricePoint(timestamp: Date(timeIntervalSince1970: TimeInterval(raw.t)), price: price)
        }
    }

    /// Fetch enhanced event data with all markets expanded
    func fetchEventDetails(slug: String) async throws -> PolymarketEvent {
        let url = URL(string: "\(gammaBaseURL)/events?slug=\(slug)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PolymarketServiceError.invalidResponse
        }

        let events = try JSONDecoder().decode([PolymarketEvent].self, from: data)
        guard let event = events.first else {
            throw PolymarketServiceError.noData
        }
        return event
    }

    /// Search markets by query
    func searchEvents(query: String, limit: Int = 20) async throws -> [PolymarketEvent] {
        var components = URLComponents(string: "\(gammaBaseURL)/events")!
        components.queryItems = [
            URLQueryItem(name: "active", value: "true"),
            URLQueryItem(name: "closed", value: "false"),
            URLQueryItem(name: "title_contains", value: query),
            URLQueryItem(name: "order", value: "volume24hr"),
            URLQueryItem(name: "ascending", value: "false"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw PolymarketServiceError.invalidConfig
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PolymarketServiceError.invalidResponse
        }

        return try JSONDecoder().decode([PolymarketEvent].self, from: data)
    }

    /// Fetch events by category/tag
    func fetchEventsByTag(tag: String, limit: Int = 30) async throws -> [PolymarketEvent] {
        var components = URLComponents(string: "\(gammaBaseURL)/events")!
        components.queryItems = [
            URLQueryItem(name: "active", value: "true"),
            URLQueryItem(name: "closed", value: "false"),
            URLQueryItem(name: "tag_slug", value: tag),
            URLQueryItem(name: "order", value: "volume24hr"),
            URLQueryItem(name: "ascending", value: "false"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw PolymarketServiceError.invalidConfig
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PolymarketServiceError.invalidResponse
        }

        return try JSONDecoder().decode([PolymarketEvent].self, from: data)
    }

    /// Fetch all available tags/categories
    func fetchTags() async throws -> [PolymarketTag] {
        let url = URL(string: "\(gammaBaseURL)/tags?_limit=100")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PolymarketServiceError.invalidResponse
        }

        return try JSONDecoder().decode([PolymarketTag].self, from: data)
    }

    // MARK: - Feed Entry Generation

    func entries(from events: [PolymarketEvent]) -> [FeedEntry] {
        events.compactMap { event -> FeedEntry? in
            guard !event.title.isEmpty else { return nil }

            // Use leadingMarket for multi-outcome markets to get the best probability
            let leading = event.leadingMarket
            let probability = leading?.probability ?? event.primaryMarket?.yesPrice ?? 0
            let leadingLabel = leading?.label
            let isMultiOutcome = (event.markets?.count ?? 0) > 1
            let probabilityPercent = Int(probability * 100)

            // Build a rich summary with market data
            var summaryParts: [String] = []

            if probabilityPercent > 0 {
                if let label = leadingLabel, !label.isEmpty, label != "Yes" {
                    summaryParts.append("\(probabilityPercent)% \(label)")
                } else {
                    summaryParts.append("\(probabilityPercent)% chance")
                }
            }

            if let vol24 = event.volume24hr, vol24 > 0 {
                summaryParts.append("24h vol: \(event.formattedVolume24hr)")
            }

            if let totalVol = event.volume, totalVol > 0 {
                summaryParts.append("Total: \(event.formattedTotalVolume)")
            }

            let summary = summaryParts.isEmpty ? event.description : summaryParts.joined(separator: " | ")

            // Parse dates
            let publishedAt = parseDate(event.createdAt) ?? parseDate(event.updatedAt)
            let endDate = parseDate(event.endDate)

            // Get market for token IDs
            let market = leading?.market ?? event.primaryMarket

            // Create polymarket-specific metadata as JSON in contentHTML
            let polymarketData = PolymarketData(
                eventID: event.id,
                probability: probability,
                volume24hr: event.volume24hr ?? 0,
                totalVolume: event.volume ?? 0,
                outcomes: market?.parsedOutcomes ?? [],
                prices: market?.parsedPrices ?? [],
                endDate: endDate,
                commentCount: event.commentCount ?? 0,
                leadingLabel: leadingLabel,
                isMultiOutcome: isMultiOutcome
            )

            let contentHTML: String?
            if let jsonData = try? JSONEncoder().encode(polymarketData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                contentHTML = "POLYMARKET_DATA:\(jsonString)"
            } else {
                contentHTML = nil
            }

            return FeedEntry(
                externalID: "polymarket:\(event.id)",
                title: event.title,
                link: event.eventURL?.absoluteString,
                summary: summary,
                contentHTML: contentHTML,
                author: "Polymarket",
                publishedAt: publishedAt,
                imageURL: event.resolvedImageURL
            )
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value = value else { return nil }
        return PolymarketService.iso8601Formatter.date(from: value)
            ?? PolymarketService.iso8601FractionalFormatter.date(from: value)
    }

    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Helper to extract PolymarketData from Article

extension Article {
    var polymarketData: PolymarketData? {
        guard let html = contentHTML,
              html.hasPrefix("POLYMARKET_DATA:") else { return nil }
        let jsonString = String(html.dropFirst("POLYMARKET_DATA:".count))
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PolymarketData.self, from: data)
    }

    var isPolymarketArticle: Bool {
        contentHTML?.hasPrefix("POLYMARKET_DATA:") == true
    }
}
