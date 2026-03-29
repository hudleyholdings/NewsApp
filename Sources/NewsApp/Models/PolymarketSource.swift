import Foundation

// MARK: - Price History Types

enum PriceHistoryInterval: String {
    case oneHour = "1h"
    case sixHours = "6h"
    case oneDay = "1d"
    case oneWeek = "1w"
    case oneMonth = "1m"
    case threeMonths = "3m"
    case max = "max"
}

struct PricePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let price: Double

    var pricePercent: Int {
        Int(price * 100)
    }
}

struct PolymarketTag: Decodable, Identifiable {
    let id: String
    let label: String
    let slug: String
    let forceShow: Bool?
    let forceHide: Bool?

    var isVisible: Bool {
        forceHide != true
    }
}

// MARK: - Configuration Enums

enum PolymarketCategory: String, Codable, CaseIterable, Identifiable {
    case all
    case politics
    case crypto
    case sports
    case popCulture
    case business
    case science

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Categories"
        case .politics: return "Politics"
        case .crypto: return "Crypto"
        case .sports: return "Sports"
        case .popCulture: return "Pop Culture"
        case .business: return "Business"
        case .science: return "Science"
        }
    }

    var tagSlug: String? {
        switch self {
        case .all: return nil
        case .politics: return "politics"
        case .crypto: return "crypto"
        case .sports: return "sports"
        case .popCulture: return "pop-culture"
        case .business: return "business"
        case .science: return "science"
        }
    }
}

enum PolymarketSort: String, Codable, CaseIterable, Identifiable {
    case volume24hr
    case volume
    case liquidity
    case newest
    case endingSoon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .volume24hr: return "Trending (24h)"
        case .volume: return "Most Volume"
        case .liquidity: return "Most Liquidity"
        case .newest: return "Newest"
        case .endingSoon: return "Ending Soon"
        }
    }

    var orderParam: String {
        switch self {
        case .volume24hr: return "volume24hr"
        case .volume: return "volume"
        case .liquidity: return "liquidity"
        case .newest: return "createdAt"
        case .endingSoon: return "endDate"
        }
    }

    var ascending: Bool {
        switch self {
        case .endingSoon: return true
        default: return false
        }
    }
}

// MARK: - Source Configuration

struct PolymarketSourceConfig: Codable, Hashable {
    var category: PolymarketCategory
    var sort: PolymarketSort
    var maxRecords: Int
    var showResolved: Bool

    init(
        category: PolymarketCategory = .all,
        sort: PolymarketSort = .volume24hr,
        maxRecords: Int = 50,
        showResolved: Bool = false
    ) {
        self.category = category
        self.sort = sort
        self.maxRecords = maxRecords
        self.showResolved = showResolved
    }
}

// MARK: - API Response Models

struct PolymarketEvent: Decodable {
    let id: String
    let ticker: String?
    let slug: String
    let title: String
    let description: String?
    let image: String?
    let icon: String?
    let active: Bool
    let closed: Bool
    let volume: Double?
    let volume24hr: Double?
    let volume1wk: Double?
    let volume1mo: Double?
    let volume1yr: Double?
    let liquidity: Double?
    let liquidityClob: Double?
    let openInterest: Double?
    let competitive: Double?
    let startDate: String?
    let endDate: String?
    let createdAt: String?
    let updatedAt: String?
    let markets: [PolymarketMarket]?
    let commentCount: Int?
    let negRisk: Bool?
    let enableOrderBook: Bool?

    var resolvedImageURL: String? {
        image ?? icon
    }

    var primaryMarket: PolymarketMarket? {
        markets?.first
    }

    /// For grouped events, find the market with highest Yes probability (the leading outcome)
    var leadingMarket: (market: PolymarketMarket, probability: Double, label: String)? {
        guard let markets = markets, !markets.isEmpty else { return nil }

        // If only one market, use it directly
        if markets.count == 1, let market = markets.first {
            let prob = market.yesPrice ?? 0
            return (market, prob, "Yes")
        }

        // Collect all questions to find common prefix
        let allQuestions = markets.compactMap { $0.question ?? $0.groupItemTitle }
        let commonPrefix = findCommonPrefix(allQuestions)

        // For grouped events, find the market with highest Yes probability
        var bestMarket: PolymarketMarket?
        var bestProb: Double = 0
        var bestLabel: String = ""

        for market in markets {
            let prob = market.yesPrice ?? 0
            if prob > bestProb {
                bestProb = prob
                bestMarket = market
                // Extract a short label from the question
                if let question = market.question ?? market.groupItemTitle {
                    bestLabel = extractSmartLabel(from: question, commonPrefix: commonPrefix)
                }
            }
        }

        if let market = bestMarket {
            return (market, bestProb, bestLabel)
        }
        return nil
    }

    private func findCommonPrefix(_ strings: [String]) -> String {
        guard let first = strings.first, !strings.isEmpty else { return "" }
        var prefix = first

        for string in strings.dropFirst() {
            while !string.hasPrefix(prefix) && !prefix.isEmpty {
                prefix = String(prefix.dropLast())
            }
        }

        // Back up to last space if we're mid-word
        if !prefix.isEmpty, let lastSpace = prefix.lastIndex(of: " ") {
            prefix = String(prefix[...lastSpace])
        }

        return prefix
    }

    private func extractSmartLabel(from question: String, commonPrefix: String) -> String {
        // Return original question without trimming
        question
    }

    var eventURL: URL? {
        URL(string: "https://polymarket.com/event/\(slug)")
    }

    var formattedVolume24hr: String {
        guard let vol = volume24hr, vol > 0 else { return "$0" }
        if vol >= 1_000_000 {
            return String(format: "$%.1fM", vol / 1_000_000)
        } else if vol >= 1_000 {
            return String(format: "$%.0fK", vol / 1_000)
        }
        return String(format: "$%.0f", vol)
    }

    var formattedTotalVolume: String {
        guard let vol = volume, vol > 0 else { return "$0" }
        if vol >= 1_000_000 {
            return String(format: "$%.1fM", vol / 1_000_000)
        } else if vol >= 1_000 {
            return String(format: "$%.0fK", vol / 1_000)
        }
        return String(format: "$%.0f", vol)
    }
}

struct PolymarketMarket: Decodable {
    let id: String
    let question: String?
    let conditionId: String?
    let slug: String?
    let description: String?
    let outcomes: String?
    let outcomePrices: String?
    let volume: String?
    let volume1wk: Double?
    let volume1mo: Double?
    let active: Bool?
    let closed: Bool?
    let image: String?
    let icon: String?
    let endDate: String?
    let startDate: String?
    let groupItemTitle: String?
    let clobTokenIds: String?
    let orderPriceMinTickSize: Double?
    let orderMinSize: Double?

    var parsedOutcomes: [String] {
        guard let outcomes = outcomes else { return [] }
        let data = outcomes.data(using: .utf8) ?? Data()
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var parsedPrices: [Double] {
        guard let prices = outcomePrices else { return [] }
        let data = prices.data(using: .utf8) ?? Data()
        let stringPrices = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return stringPrices.compactMap { Double($0) }
    }

    var parsedTokenIds: [String] {
        guard let tokenIds = clobTokenIds else { return [] }
        let data = tokenIds.data(using: .utf8) ?? Data()
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var yesTokenId: String? {
        parsedTokenIds.first
    }

    var noTokenId: String? {
        parsedTokenIds.count > 1 ? parsedTokenIds[1] : nil
    }

    var yesPrice: Double? {
        let outcomes = parsedOutcomes
        let prices = parsedPrices
        guard let yesIndex = outcomes.firstIndex(of: "Yes"),
              yesIndex < prices.count else {
            return prices.first
        }
        return prices[yesIndex]
    }

    var noPrice: Double? {
        let outcomes = parsedOutcomes
        let prices = parsedPrices
        guard let noIndex = outcomes.firstIndex(of: "No"),
              noIndex < prices.count else {
            return prices.count > 1 ? prices[1] : nil
        }
        return prices[noIndex]
    }

    var probabilityPercent: Int {
        guard let price = yesPrice else { return 0 }
        return Int(price * 100)
    }

    var formattedProbability: String {
        "\(probabilityPercent)%"
    }
}

// MARK: - Processed Market Data (for Article display)

struct PolymarketData: Codable, Hashable {
    let eventID: String
    let probability: Double
    let volume24hr: Double
    let totalVolume: Double
    let outcomes: [String]
    let prices: [Double]
    let endDate: Date?
    let commentCount: Int
    let leadingLabel: String?
    let isMultiOutcome: Bool

    // For backwards compatibility with existing cached data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try container.decode(String.self, forKey: .eventID)
        probability = try container.decode(Double.self, forKey: .probability)
        volume24hr = try container.decode(Double.self, forKey: .volume24hr)
        totalVolume = try container.decode(Double.self, forKey: .totalVolume)
        outcomes = try container.decode([String].self, forKey: .outcomes)
        prices = try container.decode([Double].self, forKey: .prices)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        leadingLabel = try container.decodeIfPresent(String.self, forKey: .leadingLabel)
        isMultiOutcome = try container.decodeIfPresent(Bool.self, forKey: .isMultiOutcome) ?? false
    }

    init(eventID: String, probability: Double, volume24hr: Double, totalVolume: Double,
         outcomes: [String], prices: [Double], endDate: Date?, commentCount: Int,
         leadingLabel: String? = nil, isMultiOutcome: Bool = false) {
        self.eventID = eventID
        self.probability = probability
        self.volume24hr = volume24hr
        self.totalVolume = totalVolume
        self.outcomes = outcomes
        self.prices = prices
        self.endDate = endDate
        self.commentCount = commentCount
        self.leadingLabel = leadingLabel
        self.isMultiOutcome = isMultiOutcome
    }

    var probabilityPercent: Int {
        Int(probability * 100)
    }

    var formattedProbability: String {
        "\(probabilityPercent)%"
    }

    var formattedVolume24hr: String {
        if volume24hr >= 1_000_000 {
            return String(format: "$%.1fM", volume24hr / 1_000_000)
        } else if volume24hr >= 1_000 {
            return String(format: "$%.0fK", volume24hr / 1_000)
        }
        return String(format: "$%.0f", volume24hr)
    }

    var formattedTotalVolume: String {
        if totalVolume >= 1_000_000 {
            return String(format: "$%.1fM", totalVolume / 1_000_000)
        } else if totalVolume >= 1_000 {
            return String(format: "$%.0fK", totalVolume / 1_000)
        }
        return String(format: "$%.0f", totalVolume)
    }

    var timeRemaining: String? {
        guard let endDate = endDate else { return nil }
        let now = Date()
        if endDate < now { return "Ended" }

        let components = Calendar.current.dateComponents([.day, .hour], from: now, to: endDate)
        if let days = components.day, days > 0 {
            return "\(days)d left"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h left"
        }
        return "Ending soon"
    }
}
