import Foundation

enum FeedSourceKind: String, Codable {
    case rss
    case gdelt
    case polymarket
}

enum GDELTTopic: String, Codable, CaseIterable, Identifiable {
    case politics
    case elections
    case economy
    case markets
    case technology
    case science
    case health
    case climate
    case conflict
    case crime
    case business
    case media

    var id: String { rawValue }

    var label: String {
        switch self {
        case .politics: return "Politics"
        case .elections: return "Elections"
        case .economy: return "Economy"
        case .markets: return "Markets"
        case .technology: return "Technology"
        case .science: return "Science"
        case .health: return "Health"
        case .climate: return "Climate"
        case .conflict: return "Conflict"
        case .crime: return "Crime"
        case .business: return "Business"
        case .media: return "Media"
        }
    }

    var query: String {
        switch self {
        case .politics: return "politics"
        case .elections: return "election"
        case .economy: return "economy"
        case .markets: return "markets"
        case .technology: return "technology"
        case .science: return "science"
        case .health: return "health"
        case .climate: return "climate"
        case .conflict: return "conflict"
        case .crime: return "crime"
        case .business: return "business"
        case .media: return "media"
        }
    }
}

enum GDELTLanguage: String, Codable, CaseIterable, Identifiable {
    case any
    case english
    case spanish
    case french
    case german
    case portuguese
    case russian
    case arabic
    case chinese
    case japanese
    case korean
    case hindi
    case italian

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .arabic: return "Arabic"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .hindi: return "Hindi"
        case .italian: return "Italian"
        }
    }

    var code: String? {
        switch self {
        case .any: return nil
        case .english: return "eng"
        case .spanish: return "spa"
        case .french: return "fre"
        case .german: return "ger"
        case .portuguese: return "por"
        case .russian: return "rus"
        case .arabic: return "ara"
        case .chinese: return "chi"
        case .japanese: return "jpn"
        case .korean: return "kor"
        case .hindi: return "hin"
        case .italian: return "ita"
        }
    }
}

enum GDELTTimeWindow: String, Codable, CaseIterable, Identifiable {
    case sixHours
    case twelveHours
    case oneDay
    case threeDays
    case sevenDays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sixHours: return "Last 6 hours"
        case .twelveHours: return "Last 12 hours"
        case .oneDay: return "Last 24 hours"
        case .threeDays: return "Last 3 days"
        case .sevenDays: return "Last 7 days"
        }
    }

    var hours: Int {
        switch self {
        case .sixHours: return 6
        case .twelveHours: return 12
        case .oneDay: return 24
        case .threeDays: return 72
        case .sevenDays: return 168
        }
    }
}

struct GDELTSourceConfig: Codable, Hashable {
    var query: String
    var topic: GDELTTopic?
    var language: GDELTLanguage
    var country: String?
    var timeWindow: GDELTTimeWindow
    var domain: String?
    var maxRecords: Int

    init(
        query: String,
        topic: GDELTTopic? = nil,
        language: GDELTLanguage = .any,
        country: String? = nil,
        timeWindow: GDELTTimeWindow = .oneDay,
        domain: String? = nil,
        maxRecords: Int = 100
    ) {
        self.query = query
        self.topic = topic
        self.language = language
        self.country = country
        self.timeWindow = timeWindow
        self.domain = domain
        self.maxRecords = maxRecords
    }
}
