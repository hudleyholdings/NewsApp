import SwiftUI
import AppKit

struct MainSplitView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var showingFeedManager = false
    @State private var showingNewspaper = false
    @State private var showingTVView = false
    @State private var showReaderPane = true
    @State private var isReaderExpanded = false
    @State private var focusedPane: FocusedPane = .articleList
    @State private var keyMonitor: Any?

    enum FocusedPane: Equatable {
        case sidebar, articleList, reader
    }

    private var isMainView: Bool {
        !showingTVView && !showingNewspaper && !isReaderExpanded
    }

    // MARK: - Unified Toolbar (structurally stable: always 2 ToolbarItems)

    // MARK: - Header title (based on sidebar selection)

    private var headerTitle: String {
        guard let selection = feedStore.selectedSidebarItem else { return "All Feeds" }
        switch selection {
        case .feed(let id):
            return feedStore.feedName(for: id) ?? "Feed"
        case .list(let id):
            if id == FeedStore.allFeedsID { return "All Feeds" }
            if id == FeedStore.favoritesID { return "Bookmarks" }
            return feedStore.listName(for: id) ?? "Feeds"
        case .category(let name):
            return name
        case .radioBrowse:
            return "Radio"
        case .radioFavorites:
            return "Favorite Stations"
        case .radioStation(let id):
            return "Radio"
        case .radioCategory(let cat):
            return "Radio"
        }
    }

    // MARK: - Main toolbar (all controls in native toolbar = single row)

    @ToolbarContentBuilder
    private var unifiedToolbarContent: some ToolbarContent {
        // Toolbar content is always the same — never changes structurally.
        // Overlay views live OUTSIDE NavigationStack so they can't disrupt it.
        ToolbarItem(placement: .navigation) {
            mainToolbarLeadingContent
        }

        ToolbarItem(placement: .primaryAction) {
            mainToolbarTrailingContent
        }
    }

    // Extracted to avoid type-checker timeouts
    private var mainToolbarLeadingContent: some View {
        HStack(spacing: 8) {
            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Divider().frame(height: 16)

            MainWeatherWidget()

            HStack(spacing: 2) {
                HeaderBarButton(
                    icon: "rectangle.split.3x1",
                    label: "Columns",
                    isActive: !showingNewspaper && !showingTVView
                ) {
                    showingNewspaper = false
                    showingTVView = false
                }

                HeaderBarButton(
                    icon: "square.grid.2x2",
                    label: "Cards",
                    isActive: showingNewspaper
                ) {
                    showingTVView = false
                    showingNewspaper = true
                }

                HeaderBarButton(
                    icon: "tv",
                    label: "TV",
                    isActive: showingTVView
                ) {
                    showingNewspaper = false
                    showingTVView = true
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HeaderBarButton(icon: "plus", label: "Add Feed") {
                NotificationCenter.default.post(name: .openFeedManager, object: nil)
            }

            HeaderBarButton(
                icon: feedStore.isRefreshing ? nil : "arrow.clockwise",
                label: "Refresh",
                showProgress: feedStore.isRefreshing
            ) {
                Task { await feedStore.refreshAll() }
            }
            .disabled(feedStore.isRefreshing)
        }
    }

    private var mainToolbarTrailingContent: some View {
        HStack(spacing: 8) {
            HeaderSearchField(text: $feedStore.searchText)

            SettingsLink(label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            })
            .buttonStyle(.borderless)
            .help("Settings")

            if !showReaderPane {
                HeaderBarButton(
                    icon: "sidebar.trailing",
                    label: "Show Reader"
                ) {
                    withAnimation { showReaderPane = true }
                }
            }
        }
    }

    // Stable content for NavigationStack — NEVER changes structurally.
    // Overlay views (Cards, TV, Expanded Reader) live OUTSIDE NavigationStack
    // so they cannot disrupt macOS NSToolbar item reconciliation.
    private var stableMainContent: some View {
        HSplitView {
            FeedListView()
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420, alignment: .leading)
                .overlay(alignment: .top) {
                    if isMainView && focusedPane == .sidebar {
                        focusBar
                    }
                }

            ContentListView()
                .frame(minWidth: 340, idealWidth: 420, maxWidth: showReaderPane ? 560 : .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    if isMainView && focusedPane == .articleList {
                        focusBar
                    }
                }

            if showReaderPane {
                ReaderPaneView(
                    showReaderPane: $showReaderPane,
                    isExpanded: $isReaderExpanded
                )
                .frame(minWidth: 460, idealWidth: 680, maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .overlay(alignment: .top) {
                    if isMainView && focusedPane == .reader {
                        focusBar
                    }
                }
            }
        }
        .focusable(isMainView)
        .onKeyPress { key in
            guard isMainView else { return .ignored }
            return handleKeyPress(key)
        }
        .animation(.easeInOut(duration: 0.2), value: showReaderPane)
        .frame(minWidth: showReaderPane ? 1180 : 720, minHeight: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var focusBar: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.7))
            .frame(height: 2)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.15), value: focusedPane)
    }

    // MARK: - Keyboard Navigation

    private var hasLocation: Bool {
        settings.weatherLatitude != 0 && settings.weatherLongitude != 0
    }

    private var hasRadioFavorites: Bool {
        !RadioStore.shared.favorites.isEmpty
    }

    private func handleKeyPress(_ key: KeyPress) -> KeyPress.Result {
        // Tab / Shift+Tab: cycle panes
        if key.key == .tab {
            if key.modifiers.contains(.shift) {
                moveFocusLeft()
            } else {
                moveFocusRight()
            }
            return .handled
        }

        // Arrow keys handled by NSEvent monitor; handle remaining keys here
        switch key.key {
        case .return:
            handleEnter()
            return .handled
        case .escape:
            handleEscape()
            return .handled
        case .space:
            handleSpace()
            return .handled
        default:
            break
        }

        // Single-character keys (vim nav + actions)
        let char = key.characters.lowercased()
        switch char {
        case "k":
            navigateUp()
            return .handled
        case "j":
            navigateDown()
            return .handled
        case "h":
            moveFocusLeft()
            return .handled
        case "l":
            moveFocusRight()
            return .handled
        case "s":
            feedStore.toggleStarCurrentArticle()
            return .handled
        case "u":
            feedStore.toggleReadCurrentArticle()
            return .handled
        case "o":
            feedStore.openCurrentArticleInBrowser()
            return .handled
        case "r":
            Task { await feedStore.refreshAll() }
            return .handled
        case "1":
            showingNewspaper = false
            showingTVView = false
            return .handled
        case "2":
            showingTVView = false
            showingNewspaper = true
            return .handled
        case "3":
            showingNewspaper = false
            showingTVView = true
            return .handled
        default:
            break
        }

        // Shift+A: mark all as read
        if char == "a" && key.modifiers.contains(.shift) {
            feedStore.markAllAsRead(for: feedStore.selectedSidebarItem)
            return .handled
        }

        return .ignored
    }

    private func moveFocusLeft() {
        switch focusedPane {
        case .reader:
            focusedPane = .articleList
        case .articleList:
            focusedPane = .sidebar
        case .sidebar:
            break
        }
    }

    private func moveFocusRight() {
        switch focusedPane {
        case .sidebar:
            focusedPane = .articleList
        case .articleList:
            if showReaderPane {
                focusedPane = .reader
            } else if feedStore.selectedArticleID != nil {
                withAnimation { showReaderPane = true }
                focusedPane = .reader
            }
        case .reader:
            break
        }
    }

    private func navigateUp() {
        switch focusedPane {
        case .sidebar:
            feedStore.navigateSidebar(direction: -1, radioEnabled: settings.radioEnabled, hasLocation: hasLocation, hasRadioFavorites: hasRadioFavorites)
        case .articleList:
            feedStore.navigateArticle(direction: -1)
        case .reader:
            NotificationCenter.default.post(name: .scrollReader, object: nil, userInfo: ["direction": -1])
        }
    }

    private func navigateDown() {
        switch focusedPane {
        case .sidebar:
            feedStore.navigateSidebar(direction: 1, radioEnabled: settings.radioEnabled, hasLocation: hasLocation, hasRadioFavorites: hasRadioFavorites)
        case .articleList:
            feedStore.navigateArticle(direction: 1)
        case .reader:
            NotificationCenter.default.post(name: .scrollReader, object: nil, userInfo: ["direction": 1])
        }
    }

    private func handleEnter() {
        switch focusedPane {
        case .sidebar:
            focusedPane = .articleList
        case .articleList:
            if feedStore.selectedArticleID != nil {
                if showReaderPane {
                    focusedPane = .reader
                }
            }
        case .reader:
            if feedStore.selectedArticleID != nil {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isReaderExpanded = true
                }
            }
        }
    }

    private func handleEscape() {
        switch focusedPane {
        case .sidebar:
            break
        case .articleList:
            feedStore.selectedArticleID = nil
            focusedPane = .sidebar
        case .reader:
            focusedPane = .articleList
        }
    }

    private func handleSpace() {
        switch focusedPane {
        case .sidebar:
            focusedPane = .articleList
        case .articleList:
            if feedStore.selectedArticleID != nil && showReaderPane {
                focusedPane = .reader
            }
        case .reader:
            // Pass to content (scroll) — return without handling
            break
        }
    }

    // Overlay views rendered outside NavigationStack
    @ViewBuilder
    private var overlayViews: some View {
        if showingTVView {
            TVView(isPresented: $showingTVView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showingNewspaper {
            MasonryCardsView(isPresented: $showingNewspaper)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if isReaderExpanded {
            ExpandedReaderView(
                isExpanded: $isReaderExpanded,
                showReaderPane: $showReaderPane
            )
            .frame(minWidth: 800, minHeight: 600)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var feedManagerOverlay: some View {
        Group {
            if showingFeedManager {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingFeedManager = false
                        }

                    FeedManagementView(isPresented: $showingFeedManager)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                }
            }
        }
    }

    private var hasOverlay: Bool {
        showingTVView || showingNewspaper || isReaderExpanded
    }

    var body: some View {
        // NavigationStack is ALWAYS fully visible (opacity 1).
        // Setting opacity(0) on NavigationStack causes macOS to
        // garbage-collect NSToolbar items permanently.
        // Overlay views use .overlay modifier (not ZStack siblings)
        // so they don't change the NavigationStack's structural content.
        NavigationStack {
            stableMainContent
                .allowsHitTesting(!hasOverlay)
                .overlay {
                    if hasOverlay {
                        overlayViews
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                .overlay { feedManagerOverlay }
                .toolbar { unifiedToolbarContent }
                .modifier(ToolbarBackgroundModifier())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .task {
                    feedStore.loadIfNeeded()
                    feedStore.configureAutoRefresh(enabled: settings.autoRefreshEnabled, intervalMinutes: settings.refreshIntervalMinutes)
                    Task { await ContentBlockerStore.shared.load() }
                    Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        await feedStore.refreshAll()
                    }
                }
                .onChange(of: settings.autoRefreshEnabled) { _, newValue in
                    feedStore.configureAutoRefresh(enabled: newValue, intervalMinutes: settings.refreshIntervalMinutes)
                }
                .onChange(of: settings.refreshIntervalMinutes) { _, newValue in
                    feedStore.configureAutoRefresh(enabled: settings.autoRefreshEnabled, intervalMinutes: newValue)
                }
                .onChange(of: feedStore.selectedArticleID) { _, newValue in
                    if newValue != nil && !showReaderPane {
                        withAnimation { showReaderPane = true }
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFeedManager)) { _ in
            showingFeedManager = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAllFeeds)) { _ in
            Task { await feedStore.refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .increaseFontSize)) { _ in
            settings.typeScale = min(settings.typeScale + 0.1, 3.5)
        }
        .onReceive(NotificationCenter.default.publisher(for: .decreaseFontSize)) { _ in
            settings.typeScale = max(settings.typeScale - 0.1, 0.75)
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard isMainView else { return event }
                // Don't intercept when a text field or search field has focus
                if let responder = event.window?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }
                switch event.keyCode {
                case 123: // left arrow
                    moveFocusLeft()
                    return nil
                case 124: // right arrow
                    moveFocusRight()
                    return nil
                case 125: // down arrow
                    navigateDown()
                    return nil
                case 126: // up arrow
                    navigateUp()
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }
}

private struct ToolbarBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}

private struct ReaderPaneView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @Binding var showReaderPane: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        ContentReaderView(
            onExpand: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded = true
                }
            },
            onClose: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showReaderPane = false
                }
            }
        )
    }
}


// MARK: - Weather Widget for Main View

private struct MainWeatherWidget: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var weather = SharedWeatherService.shared
    @State private var showingPopover = false

    var body: some View {
        Group {
            if settings.weatherEnabled && hasLocation {
                Button {
                    showingPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        if let data = weather.current {
                            Image(systemName: data.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(data.iconColor)
                            Text("\(data.temperature)°")
                                .font(.system(size: 12, weight: .medium))
                            Text(data.city)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if weather.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .help(weather.current.map { "\($0.description) in \($0.city)\n\($0.temperature)°F • Feels like \($0.feelsLike)°F\nWind: \($0.windSpeed) mph" } ?? "Weather")
                .popover(isPresented: $showingPopover) {
                    WeatherPopover(data: weather.current, city: displayCity)
                }
                .task {
                    weather.configure(
                        city: displayCity,
                        lat: settings.weatherLatitude,
                        lon: settings.weatherLongitude
                    )
                    weather.fetchIfNeeded()
                }
                .onChange(of: settings.weatherLatitude) { _, _ in
                    weather.configure(
                        city: displayCity,
                        lat: settings.weatherLatitude,
                        lon: settings.weatherLongitude
                    )
                    weather.forceRefresh()
                }
            }
        }
    }

    private var hasLocation: Bool {
        settings.weatherLatitude != 0 && settings.weatherLongitude != 0
    }

    private var displayCity: String {
        let full = settings.weatherCity
        if let comma = full.firstIndex(of: ",") {
            return String(full[..<comma])
        }
        return full.isEmpty ? "" : full
    }
}

// MARK: - Weather Popover

private struct WeatherPopover: View {
    let data: SharedWeatherService.WeatherData?
    let city: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = data {
                // Header
                HStack {
                    Image(systemName: data.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(data.iconColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(data.temperature)°F")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                        Text(data.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                // Location
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.blue)
                    Text(city)
                        .font(.subheadline)
                }

                // Details grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    WeatherDetailRow(icon: "thermometer.medium", label: "Feels Like", value: "\(data.feelsLike)°F")
                    WeatherDetailRow(icon: "wind", label: "Wind", value: "\(data.windSpeed) mph")
                    WeatherDetailRow(icon: "humidity.fill", label: "Humidity", value: "\(data.humidity)%")
                    WeatherDetailRow(icon: "arrow.up.arrow.down", label: "High/Low", value: "\(data.high)° / \(data.low)°")
                }

                // Updated time
                Text("Updated \(data.updatedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            } else {
                Text("Loading weather...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

private struct WeatherDetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

// MARK: - Header Bar Button

private struct HeaderBarButton: View {
    let icon: String?
    let label: String
    var isActive: Bool = false
    var showProgress: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if showProgress {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(width: 28, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
        .help(label)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Header Search Field

private struct HeaderSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(width: 180)
    }
}

// MARK: - Overlay Close Button (for Cards/TV views, replacing toolbar close buttons)

private struct OverlayCloseButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .padding(.leading, 12)
        .padding(.top, 8)
    }
}

// MARK: - Shared Weather Service

@MainActor
final class SharedWeatherService: ObservableObject {
    static let shared = SharedWeatherService()

    @Published var current: WeatherData?
    @Published var isLoading = false

    private var lastFetch: Date?
    private let cacheMinutes: TimeInterval = 30

    private var configuredCity = ""
    private var configuredLat: Double = 0
    private var configuredLon: Double = 0

    struct WeatherData {
        let temperature: Int
        let feelsLike: Int
        let humidity: Int
        let windSpeed: Int
        let high: Int
        let low: Int
        let weatherCode: Int
        let isDay: Bool
        let city: String
        let updatedAt: Date

        var icon: String {
            switch weatherCode {
            case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
            case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
            case 3: return "cloud.fill"
            case 45, 48: return "cloud.fog.fill"
            case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
            case 61, 63, 65, 66, 67: return "cloud.rain.fill"
            case 71, 73, 75, 77: return "cloud.snow.fill"
            case 80, 81, 82: return "cloud.heavyrain.fill"
            case 85, 86: return "cloud.snow.fill"
            case 95, 96, 99: return "cloud.bolt.rain.fill"
            default: return "cloud.fill"
            }
        }

        var iconColor: Color {
            switch weatherCode {
            case 0: return isDay ? .yellow : .indigo
            case 1, 2: return isDay ? .orange : .purple
            case 61...67, 80...82: return .blue
            case 71...77, 85, 86: return .cyan
            case 95, 96, 99: return .purple
            default: return .gray
            }
        }

        var description: String {
            switch weatherCode {
            case 0: return "Clear sky"
            case 1: return "Mainly clear"
            case 2: return "Partly cloudy"
            case 3: return "Overcast"
            case 45, 48: return "Foggy"
            case 51, 53, 55: return "Drizzle"
            case 56, 57: return "Freezing drizzle"
            case 61, 63, 65: return "Rain"
            case 66, 67: return "Freezing rain"
            case 71, 73, 75: return "Snow"
            case 77: return "Snow grains"
            case 80, 81, 82: return "Rain showers"
            case 85, 86: return "Snow showers"
            case 95: return "Thunderstorm"
            case 96, 99: return "Thunderstorm with hail"
            default: return "Unknown"
            }
        }
    }

    private init() {}

    func configure(city: String, lat: Double, lon: Double) {
        configuredCity = city
        configuredLat = lat
        configuredLon = lon
    }

    func forceRefresh() {
        lastFetch = nil
        current = nil
        fetchIfNeeded()
    }

    func fetchIfNeeded() {
        if let last = lastFetch, Date().timeIntervalSince(last) < cacheMinutes * 60 {
            return
        }
        guard configuredLat != 0 && configuredLon != 0 else { return }
        guard !isLoading else { return }
        isLoading = true

        Task {
            await fetchWeather()
        }
    }

    private func fetchWeather() async {
        let lat = configuredLat
        let lon = configuredLon
        let city = configuredCity

        // Fetch current weather + daily high/low + hourly for humidity/feels like
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current_weather=true&temperature_unit=fahrenheit&windspeed_unit=mph&daily=temperature_2m_max,temperature_2m_min&hourly=relativehumidity_2m,apparent_temperature&timezone=auto&forecast_days=1"

        guard let url = URL(string: urlString) else {
            await MainActor.run { isLoading = false }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let currentWeather = json["current_weather"] as? [String: Any],
               let temp = currentWeather["temperature"] as? Double,
               let code = currentWeather["weathercode"] as? Int,
               let isDay = currentWeather["is_day"] as? Int,
               let windSpeed = currentWeather["windspeed"] as? Double {

                // Get daily high/low
                var high = Int(temp.rounded())
                var low = Int(temp.rounded())
                if let daily = json["daily"] as? [String: Any],
                   let maxTemps = daily["temperature_2m_max"] as? [Double],
                   let minTemps = daily["temperature_2m_min"] as? [Double],
                   let maxTemp = maxTemps.first,
                   let minTemp = minTemps.first {
                    high = Int(maxTemp.rounded())
                    low = Int(minTemp.rounded())
                }

                // Get current hour's humidity and feels like
                var humidityVal = 50
                var feelsLikeVal = Int(temp.rounded())
                if let hourly = json["hourly"] as? [String: Any],
                   let humidities = hourly["relativehumidity_2m"] as? [Int],
                   let feelsLikes = hourly["apparent_temperature"] as? [Double] {
                    // Get current hour (index based on current time)
                    let hour = Calendar.current.component(.hour, from: Date())
                    if hour < humidities.count {
                        humidityVal = humidities[hour]
                    }
                    if hour < feelsLikes.count {
                        feelsLikeVal = Int(feelsLikes[hour].rounded())
                    }
                }

                // Capture final values for sendable closure
                let finalHigh = high
                let finalLow = low
                let finalHumidity = humidityVal
                let finalFeelsLike = feelsLikeVal

                await MainActor.run {
                    self.current = WeatherData(
                        temperature: Int(temp.rounded()),
                        feelsLike: finalFeelsLike,
                        humidity: finalHumidity,
                        windSpeed: Int(windSpeed.rounded()),
                        high: finalHigh,
                        low: finalLow,
                        weatherCode: code,
                        isDay: isDay == 1,
                        city: city,
                        updatedAt: Date()
                    )
                    self.lastFetch = Date()
                    self.isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}
