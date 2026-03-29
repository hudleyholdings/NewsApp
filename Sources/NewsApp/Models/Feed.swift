import Foundation

struct Feed: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var feedURL: URL
    var siteURL: URL?
    var category: String?
    var country: String?
    var sourceKind: FeedSourceKind
    var gdeltConfig: GDELTSourceConfig?
    var polymarketConfig: PolymarketSourceConfig?
    var iconURL: URL?
    var isEnabled: Bool
    var lastUpdated: Date?
    var lastFetchedAt: Date?
    var lastAttemptAt: Date?
    var etag: String?
    var lastModified: String?
    var failureCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        feedURL: URL,
        siteURL: URL? = nil,
        category: String? = nil,
        country: String? = nil,
        sourceKind: FeedSourceKind = .rss,
        gdeltConfig: GDELTSourceConfig? = nil,
        polymarketConfig: PolymarketSourceConfig? = nil,
        iconURL: URL? = nil,
        isEnabled: Bool = true,
        lastUpdated: Date? = nil,
        lastFetchedAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        failureCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.category = category
        self.country = country
        self.sourceKind = sourceKind
        self.gdeltConfig = gdeltConfig
        self.polymarketConfig = polymarketConfig
        self.iconURL = iconURL
        self.isEnabled = isEnabled
        self.lastUpdated = lastUpdated
        self.lastFetchedAt = lastFetchedAt
        self.lastAttemptAt = lastAttemptAt
        self.etag = etag
        self.lastModified = lastModified
        self.failureCount = failureCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case feedURL
        case siteURL
        case category
        case country
        case sourceKind
        case gdeltConfig
        case polymarketConfig
        case iconURL
        case isEnabled
        case lastUpdated
        case lastFetchedAt
        case lastAttemptAt
        case etag
        case lastModified
        case failureCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        feedURL = try container.decode(URL.self, forKey: .feedURL)
        siteURL = try container.decodeIfPresent(URL.self, forKey: .siteURL)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        sourceKind = try container.decodeIfPresent(FeedSourceKind.self, forKey: .sourceKind) ?? .rss
        gdeltConfig = try container.decodeIfPresent(GDELTSourceConfig.self, forKey: .gdeltConfig)
        polymarketConfig = try container.decodeIfPresent(PolymarketSourceConfig.self, forKey: .polymarketConfig)
        iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        lastFetchedAt = try container.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
        failureCount = try container.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(feedURL, forKey: .feedURL)
        try container.encodeIfPresent(siteURL, forKey: .siteURL)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encodeIfPresent(gdeltConfig, forKey: .gdeltConfig)
        try container.encodeIfPresent(polymarketConfig, forKey: .polymarketConfig)
        try container.encodeIfPresent(iconURL, forKey: .iconURL)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
        try container.encodeIfPresent(lastFetchedAt, forKey: .lastFetchedAt)
        try container.encodeIfPresent(lastAttemptAt, forKey: .lastAttemptAt)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
        try container.encode(failureCount, forKey: .failureCount)
    }
}
