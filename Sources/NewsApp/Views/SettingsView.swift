import SwiftUI
import AppKit
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var locationManager = LocationManager()
    @State private var citySearchText = ""
    @State private var cacheUsage: CacheStorageUsage = .empty
    @State private var isClearingCache = false
    @State private var showingClearCacheAlert = false

    /// Reads the marketing version straight from the bundle so the About section always
    /// matches the build that's actually shipping (CFBundleShortVersionString, set by the
    /// build script). Build number is intentionally omitted — users care about 1.2, not
    /// the internal build counter.
    static var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(short)"
    }

    var body: some View {
        ScrollView {
            Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("Article List Style", selection: $settings.articleListStyle) {
                    ForEach(ArticleListStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Picker("List Density", selection: $settings.listDensity) {
                    ForEach(ListDensity.allCases) { density in
                        Text(density.label).tag(density)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.subheadline.weight(.semibold))
                    ThemePresetGrid(selection: $settings.typographyPreset)
                    Text("Each card previews its own fonts. Selecting one updates the preview below and applies it everywhere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }


                Picker("Reader Font", selection: $settings.readerFontFamily) {
                    ForEach(ReaderFontFamily.allCases) { family in
                        FontFamilyRow(family: family, sample: "Article text Aa Bb Cc")
                            .tag(family)
                    }
                }
                Picker("List Font", selection: $settings.listFontFamily) {
                    ForEach(ReaderFontFamily.allCases) { family in
                        FontFamilyRow(family: family, sample: "Headlines Aa Bb Cc")
                            .tag(family)
                    }
                }


                VStack(alignment: .leading) {
                    HStack {
                        Text("Type Scale")
                        Spacer()
                        Text("\(String(format: "%.2f", settings.typeScale))×")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.typeScale, in: 0.75...3.5, step: 0.05)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Line Spacing")
                        Spacer()
                        Text("\(Int(settings.readerLineSpacing)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.readerLineSpacing, in: 2...12, step: 1)
                }
            } header: {
                Text("Typography")
            }

            Section("Reading") {
                Picker("Default View", selection: $settings.defaultReaderMode) {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("Mark Read on Open", isOn: $settings.markReadOnOpen)
                Toggle("Trim Reader Boilerplate", isOn: $settings.readerCleanupEnabled)
            }

            Section("Data & Feeds") {
                Toggle("Auto Refresh", isOn: $settings.autoRefreshEnabled)
                Picker("Refresh Interval", selection: $settings.refreshIntervalMinutes) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                }


                Picker("Keep Articles For", selection: $settings.articleRetentionDays) {
                    Text("1 week").tag(7)
                    Text("2 weeks").tag(14)
                    Text("1 month").tag(30)
                    Text("3 months").tag(90)
                    Text("6 months").tag(180)
                    Text("1 year").tag(365)
                }
                Text("Older articles are automatically removed. Bookmarked articles are never deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)


                Picker("Badge Count Shows", selection: $settings.badgeCountMode) {
                    ForEach(BadgeCountMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text(settings.badgeCountMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)


                Toggle("Block Ads in Preview", isOn: $settings.blockAdsEnabled)
                Toggle("Cache Images", isOn: $settings.cacheImagesEnabled)
                cacheStorageRow
            }

            Section("Preview") {
                Toggle("Prefer Mobile Site", isOn: $settings.preferMobileSite)
                Text("Preview pages use private storage with JavaScript disabled. Use Open in Browser for full interactive publisher pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Weather & Location") {
                Toggle("Show Weather", isOn: $settings.weatherEnabled)
                Text("Shows local weather in the toolbar, Cards view, and TV view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.weatherEnabled {
                    Picker("Temperature", selection: $settings.weatherUnits) {
                        ForEach(WeatherUnits.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }

                if settings.weatherEnabled {
                    // Location method picker
                    Picker("Location Source", selection: useLocationBinding) {
                        Text("Enter City Manually").tag(false)
                        Text("Use My Location").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if settings.useLocationServices {
                        // Location services status
                        HStack(spacing: 12) {
                            if locationManager.isAuthorized {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Location Access Granted")
                                        .font(.body)
                                    if !settings.weatherCity.isEmpty {
                                        Text("Using: \(settings.weatherCity)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Detecting location...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else if locationManager.authorizationStatus == .denied {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Location Access Denied")
                                        .font(.body)
                                    Button("Open System Settings") {
                                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                }
                            } else {
                                Image(systemName: "location.circle")
                                    .foregroundStyle(.blue)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Location Permission Required")
                                        .font(.body)
                                    Button("Grant Permission") {
                                        locationManager.requestPermission()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .onChange(of: locationManager.currentLocation) { _, newLocation in
                            if let location = newLocation {
                                // Save coordinates
                                settings.weatherLatitude = location.coordinate.latitude
                                settings.weatherLongitude = location.coordinate.longitude
                                settings.weatherEnabled = true
                                // Reverse geocode to get city name
                                locationManager.reverseGeocode(location) { cityName in
                                    if let city = cityName {
                                        settings.weatherCity = city
                                    }
                                }
                            }
                        }
                        .onAppear {
                            if locationManager.isAuthorized {
                                locationManager.requestLocation()
                            }
                        }
                    } else {
                        // Manual city entry
                        HStack(spacing: 12) {
                            TextField("Search for a city...", text: $citySearchText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { searchCity() }

                            Button("Search") { searchCity() }
                                .buttonStyle(.borderedProminent)
                                .disabled(citySearchText.isEmpty)

                            if locationManager.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if !settings.weatherCity.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.blue)
                                Text(settings.weatherCity)
                                Spacer()
                                Button("Remove") {
                                    settings.weatherCity = ""
                                    settings.weatherLatitude = 0
                                    settings.weatherLongitude = 0
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                        }
                    }
                }
            }

            Section("Radio") {
                Toggle("Enable Radio", isOn: $settings.radioEnabled)
                Text("Stream news/talk radio stations from around the world.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.radioEnabled {
                    VStack(alignment: .leading) {
                        Text("Default Volume")
                        Slider(value: $settings.radioVolume, in: 0...1, step: 0.1)
                        Text("\(Int(settings.radioVolume * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Show Mini Player", isOn: $settings.radioShowMiniPlayer)
                }
            }

            Section("TV View") {
                VStack(alignment: .leading) {
                    Text("Story Duration")
                    Slider(value: Binding(
                        get: { Double(settings.tvStoryDuration) },
                        set: { settings.tvStoryDuration = Int($0) }
                    ), in: 10...60, step: 5)
                    Text("\(settings.tvStoryDuration) seconds per story")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Show Progress Bar", isOn: $settings.tvShowProgress)
                Toggle("Ken Burns Effect", isOn: $settings.tvKenBurnsEnabled)
                Toggle("Show QR Code", isOn: $settings.tvShowQRCode)
                Toggle("Autoplay", isOn: $settings.tvAutoplay)
            }

            Section("About") {
                HStack {
                    Text("News App: RSS Reader & More")
                        .font(.headline)
                    Spacer()
                    Text(Self.appVersionString)
                        .foregroundStyle(.secondary)
                }
                Text("An open-source RSS reader and news aggregator for macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("© 2024-2026 Hudley Holdings LLC")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 16) {
                    Button("Privacy Policy") {
                        if let url = Bundle.module.url(forResource: "PRIVACY", withExtension: "md") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Terms of Service") {
                        if let url = Bundle.module.url(forResource: "TERMS", withExtension: "md") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("License (MIT)") {
                        if let url = Bundle.module.url(forResource: "LICENSE", withExtension: nil) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Spacer()
                    Button("Open Log File") {
                        NSWorkspace.shared.open(AppLogger.shared.logFileURL)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            }
            .formStyle(.grouped)
        }
        .background(SettingsWindowChromeAccessor())
        .frame(minWidth: 600, idealWidth: 680, maxWidth: 800)
        .frame(minHeight: 600, idealHeight: 700, maxHeight: 900)
        .preferredColorScheme(settings.colorScheme)
        .onAppear {
            refreshCacheUsage()
        }
        .onChange(of: settings.typographyPreset) { _, newValue in
            settings.applyPreset(newValue)
        }
        .alert("Clear Cached Feed Items?", isPresented: $showingClearCacheAlert) {
            Button("Clear Cache", role: .destructive) {
                clearCachedFeedData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved article items and cached images/network responses. Feeds, categories, lists, settings, and radio stations are kept.")
        }
    }

    private var cacheStorageRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cached Feed Items & Images")
                    Text(cacheStorageDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formattedByteCount(cacheUsage.totalBytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button(isClearingCache ? "Clearing..." : "Clear Cache...", role: .destructive) {
                    showingClearCacheAlert = true
                }
                .disabled(isClearingCache || !hasCachedFeedData)
            }
        }
        .padding(.vertical, 2)
    }

    private var hasCachedFeedData: Bool {
        cacheUsage.totalBytes > 0 || !feedStore.allArticles().isEmpty
    }

    private var cacheStorageDetailText: String {
        let itemCount = feedStore.allArticles().count
        let itemWord = itemCount == 1 ? "item" : "items"
        return "\(itemCount.formatted()) saved feed \(itemWord) • Articles \(formattedByteCount(cacheUsage.articleBytes)), images/network \(formattedByteCount(cacheUsage.networkCacheBytes))"
    }

    private var useLocationBinding: Binding<Bool> {
        Binding(
            get: { settings.useLocationServices },
            set: { newValue in
                settings.useLocationServices = newValue
                if newValue {
                    locationManager.requestPermission()
                }
            }
        )
    }

    private func searchCity() {
        guard !citySearchText.isEmpty else { return }
        locationManager.searchCity(citySearchText) { result in
            if let (name, lat, lon) = result {
                settings.weatherCity = name
                settings.weatherLatitude = lat
                settings.weatherLongitude = lon
                settings.weatherEnabled = true
                citySearchText = ""
            }
        }
    }

    private func refreshCacheUsage() {
        cacheUsage = feedStore.cacheStorageUsage()
    }

    private func clearCachedFeedData() {
        isClearingCache = true
        feedStore.clearCache()
        ImagePrefetcher.shared.clearCache()
        refreshCacheUsage()
        isClearingCache = false
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 bytes" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

private struct SettingsWindowChromeAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowChromeView {
        SettingsWindowChromeView()
    }

    func updateNSView(_ nsView: SettingsWindowChromeView, context: Context) {
        nsView.applyConfiguration()
    }

    final class SettingsWindowChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyConfiguration()
        }

        func applyConfiguration() {
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.styleMask.remove([.miniaturizable, .resizable])
        }
    }
}

/// Tappable grid of theme presets. Each card renders its sample text in the
/// theme's actual fonts so the differences are visible at a glance — unlike a
/// menu Picker, which forces every row into the system font.
private struct ThemePresetGrid: View {
    @Binding var selection: TypographyPreset

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TypographyPreset.allCases) { preset in
                ThemePresetCard(preset: preset, isSelected: preset == selection) {
                    selection = preset
                }
            }
        }
    }
}

private struct ThemePresetCard: View {
    let preset: TypographyPreset
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let preview = PresetPreview(preset: preset)
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(preset.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                }

                Text("Headline Preview")
                    .font(preview.headlineFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Body text • 3 min read")
                    .font(preview.bodyFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(preview.tagline)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PresetPreview {
    let headlineFont: Font
    let bodyFont: Font
    let tagline: String

    init(preset: TypographyPreset) {
        switch preset {
        case .nightReader:
            headlineFont = .system(size: 14, weight: .semibold, design: .rounded)
            bodyFont = .system(size: 12, weight: .regular, design: .serif)
            tagline = "Serif + System"
        case .newspaperClassic:
            headlineFont = .custom("Charter", size: 15)
            bodyFont = .custom("Charter", size: 12)
            tagline = "Classic News"
        case .drudgeCondensed:
            headlineFont = .system(size: 13, weight: .semibold, design: .monospaced)
            bodyFont = .system(size: 11, weight: .regular, design: .monospaced)
            tagline = "Condensed"
        case .minimalUtility:
            headlineFont = .system(size: 13, weight: .semibold, design: .default)
            bodyFont = .system(size: 11, weight: .regular, design: .default)
            tagline = "Utility"
        case .magazine:
            headlineFont = .custom("SF Pro Display", size: 16)
            bodyFont = .custom("SF Pro Display", size: 12)
            tagline = "Magazine"
        case .metroWire:
            headlineFont = .custom("Avenir Next", size: 15)
            bodyFont = .custom("Avenir Next", size: 12)
            tagline = "Metro Wire"
        case .monoLedger:
            headlineFont = .system(size: 13, weight: .semibold, design: .monospaced)
            bodyFont = .system(size: 11, weight: .regular, design: .monospaced)
            tagline = "Ledger"
        case .quietSerif:
            headlineFont = .custom("Palatino", size: 15)
            bodyFont = .custom("Palatino", size: 12)
            tagline = "Quiet Serif"
        case .roundDeck:
            headlineFont = .system(size: 14, weight: .semibold, design: .rounded)
            bodyFont = .system(size: 12, weight: .regular, design: .rounded)
            tagline = "Round"
        case .compactPro:
            headlineFont = .system(size: 12, weight: .semibold, design: .default)
            bodyFont = .system(size: 10, weight: .regular, design: .default)
            tagline = "Compact"
        }
    }
}

private struct FontFamilyRow: View {
    let family: ReaderFontFamily
    let sample: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(family.label)
                .font(.headline)
            Text(sample)
                .font(SettingsStore.previewFont(family: family, size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Location Manager

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isSearching = false

    var isAuthorized: Bool {
        #if os(macOS)
        return authorizationStatus == .authorized || authorizationStatus == .authorizedAlways
        #else
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #endif
    }

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        if CLLocationManager.locationServicesEnabled() {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestLocation() {
        if CLLocationManager.locationServicesEnabled() {
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAuthorized {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.currentLocation = locations.first
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.shared.log("Location error: \(error)")
    }

    // Reverse geocode coordinates to city name
    func reverseGeocode(_ location: CLLocation, completion: @escaping @MainActor (String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            Task { @MainActor in
                guard let placemark = placemarks?.first, error == nil else {
                    completion(nil)
                    return
                }
                var parts = [String]()
                if let city = placemark.locality {
                    parts.append(city)
                }
                if let state = placemark.administrativeArea {
                    parts.append(state)
                }
                if let country = placemark.country, placemark.isoCountryCode != "US" {
                    parts.append(country)
                }
                completion(parts.isEmpty ? nil : parts.joined(separator: ", "))
            }
        }
    }

    // Geocode city name using Open-Meteo's geocoding API (free, no key)
    func searchCity(_ query: String, completion: @escaping @MainActor ((String, Double, Double)?) -> Void) {
        isSearching = true

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json"

        guard let url = URL(string: urlString) else {
            Task { @MainActor in
                self.isSearching = false
                completion(nil)
            }
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            Task { @MainActor in
                self?.isSearching = false

                guard let data = data, error == nil else {
                    completion(nil)
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [[String: Any]],
                       let first = results.first,
                       let name = first["name"] as? String,
                       let lat = first["latitude"] as? Double,
                       let lon = first["longitude"] as? Double {
                        // Include country/admin for disambiguation
                        let admin = first["admin1"] as? String
                        let country = first["country"] as? String
                        var fullName = name
                        if let admin = admin { fullName += ", \(admin)" }
                        if let country = country { fullName += ", \(country)" }
                        completion((fullName, lat, lon))
                    } else {
                        completion(nil)
                    }
                } catch {
                    completion(nil)
                }
            }
        }.resume()
    }
}
