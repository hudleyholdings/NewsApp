import SwiftUI
import AppKit
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var locationManager = LocationManager()
    @State private var showPersistentAlert = false
    @State private var citySearchText = ""

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
                Picker("Quick Preset", selection: $settings.typographyPreset) {
                    ForEach(TypographyPreset.allCases) { preset in
                        PresetRow(preset: preset).tag(preset)
                    }
                }
                Text("Presets adjust fonts, scale, and spacing together. Fine-tune below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)


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


                Toggle("Block Ads in Web View", isOn: $settings.blockAdsEnabled)
                Toggle("Cache Images", isOn: $settings.cacheImagesEnabled)
            }

            Section("Web View") {
                Toggle("Prefer Mobile Site", isOn: $settings.preferMobileSite)
                Toggle("Allow Persistent Sessions (Keychain)", isOn: persistentSessionBinding)
                Text("When enabled, web pages can store secure keys in your Keychain for logins. Off = Private Web Mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Weather & Location") {
                Toggle("Show Weather in Newspaper View", isOn: $settings.weatherEnabled)

                if settings.weatherEnabled {
                    Divider()

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
                    Text("NewsApp")
                        .font(.headline)
                    Spacer()
                    Text("Version 1.0")
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
        .frame(minWidth: 600, idealWidth: 680, maxWidth: 800)
        .frame(minHeight: 600, idealHeight: 700, maxHeight: 900)
        .preferredColorScheme(settings.colorScheme)
        .onChange(of: settings.typographyPreset) { _, newValue in
            settings.applyPreset(newValue)
        }
        .alert("Enable Persistent Sessions?", isPresented: $showPersistentAlert) {
            Button("Enable") { settings.persistentWebSessions = true }
            Button("Cancel", role: .cancel) { settings.persistentWebSessions = false }
        } message: {
            Text("Some sites use WebCrypto and will prompt macOS to store a key in your Keychain. Enable this only if you want persistent logins and sessions.")
        }
    }

    private var persistentSessionBinding: Binding<Bool> {
        Binding(
            get: { settings.persistentWebSessions },
            set: { newValue in
                if newValue {
                    showPersistentAlert = true
                } else {
                    settings.persistentWebSessions = false
                }
            }
        )
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
                citySearchText = ""
            }
        }
    }
}

private struct PresetRow: View {
    let preset: TypographyPreset

    var body: some View {
        let preview = PresetPreview(preset: preset)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.label)
                    .font(.headline)
                Text("Headline Preview")
                    .font(preview.headlineFont)
                Text("Body preview text • 3 min read")
                    .font(preview.bodyFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(preview.tagline)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
        #if os(macOS)
        // On macOS, we need to request always authorization for location
        if CLLocationManager.locationServicesEnabled() {
            manager.requestAlwaysAuthorization()
        }
        #else
        manager.requestWhenInUseAuthorization()
        #endif
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
