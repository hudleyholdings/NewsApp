import SwiftUI

/// Temperature + wind units for the weather widgets.
enum WeatherUnits: String, CaseIterable, Identifiable, Codable {
    case fahrenheit
    case celsius

    var id: String { rawValue }

    /// Sensible initial value for the onboarding picker. Derived from the user's locale
    /// (US uses Fahrenheit; everyone else uses Celsius). The user can override in the
    /// onboarding step or later in Settings.
    static var systemDefault: WeatherUnits {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    var temperatureSymbol: String {
        switch self {
        case .fahrenheit: return "°F"
        case .celsius: return "°C"
        }
    }

    /// Short suffix for display in the toolbar (no extra space — e.g. "72°").
    var temperatureSuffixShort: String { "°" }

    var windSpeedLabel: String {
        switch self {
        case .fahrenheit: return "mph"
        case .celsius: return "km/h"
        }
    }

    /// Open-Meteo's URL query value for `temperature_unit`.
    var openMeteoTemperatureParameter: String {
        switch self {
        case .fahrenheit: return "fahrenheit"
        case .celsius: return "celsius"
        }
    }

    /// Open-Meteo's URL query value for `windspeed_unit`.
    var openMeteoWindspeedParameter: String {
        switch self {
        case .fahrenheit: return "mph"
        case .celsius: return "kmh"
        }
    }

    var displayName: String {
        switch self {
        case .fahrenheit: return "Fahrenheit"
        case .celsius: return "Celsius"
        }
    }
}

/// Sort order for categories and the feeds inside them in the sidebar.
enum SidebarSortMode: String, CaseIterable, Identifiable, Codable {
    case alphabetical
    case byUnreadCount
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alphabetical: return "Alphabetical"
        case .byUnreadCount: return "Unread Count"
        case .custom: return "Custom Order"
        }
    }
}

enum SidebarCustomOrderItemKind: String, Codable {
    case list
    case category
}

struct SidebarCustomOrderItem: Codable, Hashable, Identifiable {
    var kind: SidebarCustomOrderItemKind
    var value: String

    var id: String { "\(kind.rawValue):\(value)" }

    static func list(_ id: UUID) -> SidebarCustomOrderItem {
        SidebarCustomOrderItem(kind: .list, value: id.uuidString)
    }

    static func category(_ name: String) -> SidebarCustomOrderItem {
        SidebarCustomOrderItem(kind: .category, value: name)
    }
}

enum BadgeCountMode: String, CaseIterable, Identifiable, Codable {
    case unread
    case newSinceSession
    case newSinceRefresh

    var id: String { rawValue }
    var label: String {
        switch self {
        case .unread: return "Unread"
        case .newSinceSession: return "New This Session"
        case .newSinceRefresh: return "New Since Refresh"
        }
    }

    var shortLabel: String {
        switch self {
        case .unread: return "unread"
        case .newSinceSession: return "new"
        case .newSinceRefresh: return "new"
        }
    }

    var description: String {
        switch self {
        case .unread: return "Total articles you haven't read"
        case .newSinceSession: return "Articles added since the app launched"
        case .newSinceRefresh: return "Articles added since the last refresh"
        }
    }
}

final class SettingsStore: ObservableObject {
    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .dark
    @AppStorage("readerFontFamily") var readerFontFamily: ReaderFontFamily = .serif
    @AppStorage("readerFontSize") var readerFontSize: Double = 18
    @AppStorage("readerLineSpacing") var readerLineSpacing: Double = 6
    @AppStorage("readerMaxWidth") var readerMaxWidth: Double = 720
    @AppStorage("typeScale") var typeScale: Double = 1.0
    @AppStorage("listDensity") var listDensity: ListDensity = .comfortable
    @AppStorage("defaultReaderMode") var defaultReaderMode: ReaderDisplayMode = .reader
    @AppStorage("articleListStyle") var articleListStyle: ArticleListStyle = .standard
    @AppStorage("listFontFamily") var listFontFamily: ReaderFontFamily = .sans
    @AppStorage("typographyPreset") var typographyPreset: TypographyPreset = .nightReader
    @AppStorage("feedTitleSize") var feedTitleSize: Double = 13
    @AppStorage("feedSubtitleSize") var feedSubtitleSize: Double = 11
    @AppStorage("articleTitleSize") var articleTitleSize: Double = 14
    @AppStorage("articleSummarySize") var articleSummarySize: Double = 12
    @AppStorage("articleMetaSize") var articleMetaSize: Double = 11
    @AppStorage("markReadOnOpen") var markReadOnOpen: Bool = true
    @AppStorage("readerCleanupEnabled") var readerCleanupEnabled: Bool = true
    @AppStorage("autoRefreshEnabled") var autoRefreshEnabled: Bool = true
    @AppStorage("refreshIntervalMinutes") var refreshIntervalMinutes: Int = 30
    @AppStorage("blockAdsEnabled") var blockAdsEnabled: Bool = true
    @AppStorage("cacheImagesEnabled") var cacheImagesEnabled: Bool = true
    @AppStorage("preferMobileSite") var preferMobileSite: Bool = false

    // Weather & Location
    @AppStorage("weatherEnabled") var weatherEnabled: Bool = false
    @AppStorage("weatherCity") var weatherCity: String = ""
    @AppStorage("weatherLatitude") var weatherLatitude: Double = 0
    @AppStorage("weatherLongitude") var weatherLongitude: Double = 0
    @AppStorage("useLocationServices") var useLocationServices: Bool = false
    @AppStorage("weatherUnits") var weatherUnits: WeatherUnits = WeatherUnits.systemDefault

    // TV View Settings
    @AppStorage("tvStoryDuration") var tvStoryDuration: Int = 20
    @AppStorage("tvShowProgress") var tvShowProgress: Bool = true
    @AppStorage("tvKenBurnsEnabled") var tvKenBurnsEnabled: Bool = true
    @AppStorage("tvAutoplay") var tvAutoplay: Bool = true
    @AppStorage("tvShowQRCode") var tvShowQRCode: Bool = true

    // Radio Settings
    @AppStorage("radioEnabled") var radioEnabled: Bool = true
    @AppStorage("radioVolume") var radioVolume: Double = 0.8
    @AppStorage("radioShowMiniPlayer") var radioShowMiniPlayer: Bool = true

    // Data Retention Settings
    @AppStorage("articleRetentionDays") var articleRetentionDays: Int = 30

    // Badge Count Settings
    @AppStorage("badgeCountMode") var badgeCountMode: BadgeCountMode = .unread

    // Sidebar controls
    @AppStorage("sidebarFilterUnreadOnly") var sidebarFilterUnreadOnly: Bool = false
    @AppStorage("sidebarSortMode") var sidebarSortMode: SidebarSortMode = .alphabetical
    /// JSON-encoded array of category names that are currently collapsed in the sidebar.
    /// Stored via `@AppStorage` as a String so `Set<String>` can persist across launches;
    /// access through `collapsedCategories` rather than this raw property.
    @AppStorage("collapsedCategoriesJSON") var collapsedCategoriesJSON: String = "[]"
    /// JSON-encoded UUID strings for collapsed custom/user lists in the sidebar.
    @AppStorage("collapsedListIDsJSON") var collapsedListIDsJSON: String = "[]"
    /// JSON-encoded array of category names in the user's preferred order. Used when
    /// `sidebarSortMode == .custom`. Survives changes to the sort mode so switching
    /// back to Custom restores the last-saved order.
    @AppStorage("customCategoryOrderJSON") var customCategoryOrderJSON: String = "[]"
    /// JSON-encoded flat order for reorderable sidebar rows in Custom Order mode.
    /// Smart lists stay fixed; user lists and feed categories share this order.
    @AppStorage("customSidebarItemOrderJSON") var customSidebarItemOrderJSON: String = "[]"

    /// User-collapsed category names. Backed by `collapsedCategoriesJSON` so changes
    /// persist and trigger SwiftUI re-renders through `@AppStorage` observation.
    var collapsedCategories: Set<String> {
        get {
            guard let data = collapsedCategoriesJSON.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(array)
        }
        set {
            let sorted = Array(newValue).sorted()
            if let data = try? JSONEncoder().encode(sorted),
               let json = String(data: data, encoding: .utf8) {
                collapsedCategoriesJSON = json
            }
        }
    }

    var collapsedListIDs: Set<UUID> {
        get {
            guard let data = collapsedListIDsJSON.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(array.compactMap(UUID.init(uuidString:)))
        }
        set {
            let sorted = newValue.map(\.uuidString).sorted()
            if let data = try? JSONEncoder().encode(sorted),
               let json = String(data: data, encoding: .utf8) {
                collapsedListIDsJSON = json
            }
        }
    }

    /// Ordered list of category names for `.custom` sort. Categories not in the list
    /// fall through to alphabetical (so newly-added categories don't disappear).
    var customCategoryOrder: [String] {
        get {
            guard let data = customCategoryOrderJSON.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                customCategoryOrderJSON = json
            }
        }
    }

    var customSidebarItemOrder: [SidebarCustomOrderItem] {
        get {
            guard let data = customSidebarItemOrderJSON.data(using: .utf8),
                  let array = try? JSONDecoder().decode([SidebarCustomOrderItem].self, from: data) else {
                return []
            }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                customSidebarItemOrderJSON = json
            }
        }
    }

    func toggleCategoryCollapsed(_ category: String) {
        var current = collapsedCategories
        if current.contains(category) {
            current.remove(category)
        } else {
            current.insert(category)
        }
        collapsedCategories = current
    }

    func toggleListCollapsed(_ id: UUID) {
        var current = collapsedListIDs
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        collapsedListIDs = current
    }

    func collapseAllCategories(_ categories: [String]) {
        collapsedCategories = Set(categories)
    }

    func expandAllCategories() {
        collapsedCategories = []
    }

    func collapseAllLists(_ ids: [UUID]) {
        collapsedListIDs = Set(ids)
    }

    func expandAllLists() {
        collapsedListIDs = []
    }

    // Onboarding
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false

    // TV View typography helper
    func tvFont(size: Double, weight: Font.Weight = .regular) -> Font {
        // Use display font for TV view - clean and readable on screen
        return .system(size: scaled(size), weight: weight, design: .default)
    }

    func tvHeadlineFont(size: Double) -> Font {
        // Use reader font family for headlines to respect user preference
        return readerFont(size: size, weight: .bold)
    }

    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    var readerFont: Font {
        switch readerFontFamily {
        case .serif:
            return .system(size: scaled(readerFontSize), weight: .regular, design: .serif)
        case .sans:
            return .system(size: scaled(readerFontSize), weight: .regular, design: .default)
        case .rounded:
            return .system(size: scaled(readerFontSize), weight: .regular, design: .rounded)
        case .mono:
            return .system(size: scaled(readerFontSize), weight: .regular, design: .monospaced)
        case .classic:
            return .custom("New York", size: scaled(readerFontSize))
        case .display:
            return .custom("SF Pro Display", size: scaled(readerFontSize))
        case .georgia:
            return .custom("Georgia", size: scaled(readerFontSize))
        case .avenir:
            return .custom("Avenir Next", size: scaled(readerFontSize))
        case .palatino:
            return .custom("Palatino", size: scaled(readerFontSize))
        case .charter:
            return .custom("Charter", size: scaled(readerFontSize))
        }
    }

    func readerFont(size: Double, weight: Font.Weight = .regular) -> Font {
        let scaledSize = scaled(size)
        switch readerFontFamily {
        case .serif:
            return .system(size: scaledSize, weight: weight, design: .serif)
        case .sans:
            return .system(size: scaledSize, weight: weight, design: .default)
        case .rounded:
            return .system(size: scaledSize, weight: weight, design: .rounded)
        case .mono:
            return .system(size: scaledSize, weight: weight, design: .monospaced)
        case .classic:
            return .custom("New York", size: scaledSize).weight(weight)
        case .display:
            return .custom("SF Pro Display", size: scaledSize).weight(weight)
        case .georgia:
            return .custom("Georgia", size: scaledSize).weight(weight)
        case .avenir:
            return .custom("Avenir Next", size: scaledSize).weight(weight)
        case .palatino:
            return .custom("Palatino", size: scaledSize).weight(weight)
        case .charter:
            return .custom("Charter", size: scaledSize).weight(weight)
        }
    }

    func listFont(size: Double, weight: Font.Weight = .regular) -> Font {
        let scaledSize = scaled(size)
        switch listFontFamily {
        case .serif:
            return .system(size: scaledSize, weight: weight, design: .serif)
        case .sans:
            return .system(size: scaledSize, weight: weight, design: .default)
        case .rounded:
            return .system(size: scaledSize, weight: weight, design: .rounded)
        case .mono:
            return .system(size: scaledSize, weight: weight, design: .monospaced)
        case .classic:
            return .custom("New York", size: scaledSize).weight(weight)
        case .display:
            return .custom("SF Pro Display", size: scaledSize).weight(weight)
        case .georgia:
            return .custom("Georgia", size: scaledSize).weight(weight)
        case .avenir:
            return .custom("Avenir Next", size: scaledSize).weight(weight)
        case .palatino:
            return .custom("Palatino", size: scaledSize).weight(weight)
        case .charter:
            return .custom("Charter", size: scaledSize).weight(weight)
        }
    }

    func scaled(_ value: Double) -> Double {
        max(0.75, min(3.5, typeScale)) * value
    }
}

extension SettingsStore {
    static func previewFont(family: ReaderFontFamily, size: Double, weight: Font.Weight = .regular) -> Font {
        switch family {
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .sans:
            return .system(size: size, weight: weight, design: .default)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .mono:
            return .system(size: size, weight: weight, design: .monospaced)
        case .classic:
            return .custom("New York", size: size).weight(weight)
        case .display:
            return .custom("SF Pro Display", size: size).weight(weight)
        case .georgia:
            return .custom("Georgia", size: size).weight(weight)
        case .avenir:
            return .custom("Avenir Next", size: size).weight(weight)
        case .palatino:
            return .custom("Palatino", size: size).weight(weight)
        case .charter:
            return .custom("Charter", size: size).weight(weight)
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case dark
    case light

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable {
    case serif
    case sans
    case rounded
    case mono
    case classic
    case display
    case georgia
    case avenir
    case palatino
    case charter

    var id: String { rawValue }
    var label: String {
        switch self {
        case .serif: return "Serif"
        case .sans: return "System"
        case .rounded: return "Rounded"
        case .mono: return "Mono"
        case .classic: return "Classic"
        case .display: return "Display"
        case .georgia: return "Georgia"
        case .avenir: return "Avenir"
        case .palatino: return "Palatino"
        case .charter: return "Charter"
        }
    }
}

enum ListDensity: String, CaseIterable, Identifiable, Codable {
    case comfortable
    case compact

    var id: String { rawValue }
    var label: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
        }
    }

    var rowSpacing: CGFloat {
        switch self {
        case .comfortable: return 12
        case .compact: return 6
        }
    }

    var summaryLines: Int {
        switch self {
        case .comfortable: return 2
        case .compact: return 1
        }
    }
}

enum ReaderDisplayMode: String, CaseIterable, Identifiable, Codable {
    case reader
    case web

    var id: String { rawValue }
    var label: String {
        switch self {
        case .reader: return "Reader"
        case .web: return "Preview"
        }
    }
}

enum ArticleListStyle: String, CaseIterable, Identifiable, Codable {
    case standard
    case newspaper

    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "Standard"
        case .newspaper: return "Newspaper"
        }
    }
}

enum TypographyPreset: String, CaseIterable, Identifiable, Codable {
    case nightReader
    case newspaperClassic
    case drudgeCondensed
    case minimalUtility
    case magazine
    case metroWire
    case monoLedger
    case quietSerif
    case roundDeck
    case compactPro

    var id: String { rawValue }
    var label: String {
        switch self {
        case .nightReader: return "Night Reader"
        case .newspaperClassic: return "Newspaper Classic"
        case .drudgeCondensed: return "Drudge Condensed"
        case .minimalUtility: return "Minimal Utility"
        case .magazine: return "Magazine"
        case .metroWire: return "Metro Wire"
        case .monoLedger: return "Mono Ledger"
        case .quietSerif: return "Quiet Serif"
        case .roundDeck: return "Round Deck"
        case .compactPro: return "Compact Pro"
        }
    }
}

extension SettingsStore {
    func applyPreset(_ preset: TypographyPreset) {
        typographyPreset = preset
        typeScale = 1.0
        switch preset {
        case .nightReader:
            readerFontFamily = .serif
            readerFontSize = 19
            readerLineSpacing = 7
            readerMaxWidth = 720
            listFontFamily = .sans
            listDensity = .comfortable
            articleListStyle = .standard
            feedTitleSize = 13
            feedSubtitleSize = 11
            articleTitleSize = 15
            articleSummarySize = 12
            articleMetaSize = 11
        case .newspaperClassic:
            readerFontFamily = .charter
            readerFontSize = 18
            readerLineSpacing = 6
            readerMaxWidth = 700
            listFontFamily = .charter
            listDensity = .comfortable
            articleListStyle = .newspaper
            feedTitleSize = 13
            feedSubtitleSize = 11
            articleTitleSize = 16
            articleSummarySize = 12
            articleMetaSize = 10
        case .drudgeCondensed:
            readerFontFamily = .sans
            readerFontSize = 17
            readerLineSpacing = 5
            readerMaxWidth = 680
            listFontFamily = .mono
            listDensity = .compact
            articleListStyle = .newspaper
            feedTitleSize = 12
            feedSubtitleSize = 10
            articleTitleSize = 13
            articleSummarySize = 10
            articleMetaSize = 9
        case .minimalUtility:
            readerFontFamily = .sans
            readerFontSize = 17
            readerLineSpacing = 5
            readerMaxWidth = 680
            listFontFamily = .sans
            listDensity = .compact
            articleListStyle = .standard
            feedTitleSize = 12
            feedSubtitleSize = 10
            articleTitleSize = 13
            articleSummarySize = 11
            articleMetaSize = 9
        case .magazine:
            readerFontFamily = .display
            readerFontSize = 20
            readerLineSpacing = 8
            readerMaxWidth = 780
            listFontFamily = .display
            listDensity = .comfortable
            articleListStyle = .standard
            feedTitleSize = 14
            feedSubtitleSize = 12
            articleTitleSize = 18
            articleSummarySize = 14
            articleMetaSize = 11
        case .metroWire:
            readerFontFamily = .avenir
            readerFontSize = 18
            readerLineSpacing = 6
            readerMaxWidth = 720
            listFontFamily = .avenir
            listDensity = .comfortable
            articleListStyle = .standard
            feedTitleSize = 13
            feedSubtitleSize = 11
            articleTitleSize = 16
            articleSummarySize = 12
            articleMetaSize = 10
        case .monoLedger:
            readerFontFamily = .mono
            readerFontSize = 17
            readerLineSpacing = 5
            readerMaxWidth = 700
            listFontFamily = .mono
            listDensity = .compact
            articleListStyle = .newspaper
            feedTitleSize = 12
            feedSubtitleSize = 10
            articleTitleSize = 13
            articleSummarySize = 10
            articleMetaSize = 9
        case .quietSerif:
            readerFontFamily = .palatino
            readerFontSize = 19
            readerLineSpacing = 7
            readerMaxWidth = 740
            listFontFamily = .palatino
            listDensity = .comfortable
            articleListStyle = .standard
            feedTitleSize = 13
            feedSubtitleSize = 11
            articleTitleSize = 15
            articleSummarySize = 12
            articleMetaSize = 10
        case .roundDeck:
            readerFontFamily = .rounded
            readerFontSize = 18
            readerLineSpacing = 6
            readerMaxWidth = 710
            listFontFamily = .rounded
            listDensity = .comfortable
            articleListStyle = .standard
            feedTitleSize = 13
            feedSubtitleSize = 11
            articleTitleSize = 16
            articleSummarySize = 12
            articleMetaSize = 10
        case .compactPro:
            readerFontFamily = .sans
            readerFontSize = 16
            readerLineSpacing = 4
            readerMaxWidth = 640
            listFontFamily = .sans
            listDensity = .compact
            articleListStyle = .standard
            feedTitleSize = 11
            feedSubtitleSize = 9
            articleTitleSize = 12
            articleSummarySize = 10
            articleMetaSize = 9
        }
    }
}
