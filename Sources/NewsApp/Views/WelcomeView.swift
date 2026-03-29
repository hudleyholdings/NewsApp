import SwiftUI
import AppKit
import CoreLocation

struct WelcomeView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var locationManager = LocationManager()
    @State private var step: Step = .welcome
    @State private var feedURL = ""
    @State private var isAddingFeed = false
    @State private var feedError: String?
    @State private var addedFeeds: [String] = []
    @State private var citySearchText = ""
    @State private var starterPackLoaded = false

    enum Step {
        case welcome
        case appearance
        case feeds
        case weather
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                switch step {
                case .welcome:
                    welcomeStep
                case .appearance:
                    appearanceStep
                case .feeds:
                    feedsStep
                case .weather:
                    weatherStep
                }
            }
            .frame(maxWidth: 520)
            .padding(40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("Welcome to NewsApp")
                .font(.system(size: 28, weight: .bold, design: .serif))

            Text("A fast, native RSS reader for macOS.\nLet's get you set up.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Get Started") {
                withAnimation { step = .appearance }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Appearance

    private var appearanceStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "textformat.size")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Choose Your Look")
                    .font(.system(size: 24, weight: .bold, design: .serif))

                Text("Pick a theme and typography preset. You can change these later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Theme picker
            HStack(spacing: 12) {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        settings.appearanceMode = mode
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(mode == .dark ? Color.black : (mode == .light ? Color.white : Color.gray.opacity(0.3)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(settings.appearanceMode == mode ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: settings.appearanceMode == mode ? 2 : 1)
                                )
                                .frame(width: 72, height: 48)
                            Text(mode.label)
                                .font(.caption)
                                .foregroundStyle(settings.appearanceMode == mode ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.vertical, 4)

            // Typography presets - scrollable grid
            Text("Typography")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(TypographyPreset.allCases) { preset in
                        Button {
                            settings.applyPreset(preset)
                        } label: {
                            OnboardingPresetRow(preset: preset, isSelected: settings.typographyPreset == preset, scale: settings.typeScale)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)

            // Type scale
            VStack(spacing: 4) {
                HStack {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(String(format: "%.0f%%", settings.typeScale * 100))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.typeScale, in: 0.75...2.0, step: 0.05)
            }

            HStack {
                Spacer()
                Button("Next") {
                    withAnimation { step = .feeds }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Feeds

    private var feedsStep: some View {
        VStack(spacing: 20) {
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 56, height: 56)
            }

            VStack(spacing: 8) {
                Text("Add Your Feeds")
                    .font(.system(size: 24, weight: .bold, design: .serif))

                Text("Paste any website or feed URL, import from another reader, or start with a curated starter pack.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Add by URL
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("e.g. nytimes.com or a feed URL", text: $feedURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addFeed() }

                    Button("Add") { addFeed() }
                        .buttonStyle(.borderedProminent)
                        .disabled(feedURL.isEmpty || isAddingFeed)

                    if isAddingFeed {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let error = feedError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !addedFeeds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(addedFeeds, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(name)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
            }

            Divider().padding(.vertical, 4)

            // Quick actions
            HStack(spacing: 16) {
                Button {
                    importOPML()
                } label: {
                    Label("Import OPML", systemImage: "doc.badge.plus")
                }

                Button {
                    loadStarterPack()
                } label: {
                    Label("Load Starter Pack", systemImage: "star.fill")
                }
                .disabled(starterPackLoaded)
            }
            .buttonStyle(.bordered)

            Text("The starter pack includes 60+ feeds from major news outlets across world news, tech, business, science, and more.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 4)

            HStack {
                Button("Skip") {
                    withAnimation { step = .weather }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Next") {
                    withAnimation { step = .weather }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Weather

    private var weatherStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange, .blue)

            VStack(spacing: 8) {
                Text("Set Your Location")
                    .font(.system(size: 24, weight: .bold, design: .serif))

                Text("Optional. Shows local weather in the toolbar and newspaper view.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Location method
            Picker("", selection: locationMethodBinding) {
                Text("Enter City").tag(false)
                Text("Use My Location").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if settings.useLocationServices {
                // Auto-detect location
                if locationManager.isAuthorized {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Location Access Granted")
                                .font(.body)
                            if !settings.weatherCity.isEmpty {
                                Text(settings.weatherCity)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Detecting...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
                } else if locationManager.authorizationStatus == .denied {
                    HStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Location Access Denied")
                            Button("Open System Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
                } else {
                    Button {
                        locationManager.requestPermission()
                    } label: {
                        Label("Grant Location Permission", systemImage: "location.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Manual city entry
                HStack(spacing: 8) {
                    TextField("Search for a city...", text: $citySearchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { searchCity() }

                    Button("Search") { searchCity() }
                        .buttonStyle(.borderedProminent)
                        .disabled(citySearchText.isEmpty)

                    if locationManager.isSearching {
                        ProgressView().controlSize(.small)
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
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                }
            }

            Spacer().frame(height: 8)

            HStack {
                Button("Back") {
                    withAnimation { step = .feeds }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Finish Setup") {
                    settings.weatherEnabled = settings.weatherLatitude != 0
                    settings.hasCompletedOnboarding = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            if let location = newLocation {
                settings.weatherLatitude = location.coordinate.latitude
                settings.weatherLongitude = location.coordinate.longitude
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
    }

    // MARK: - Helpers

    private var locationMethodBinding: Binding<Bool> {
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

    private func loadStarterPack() {
        let seedFeeds = feedStore.loadSeedFeeds()
        let existing = Set(feedStore.feeds.map { $0.feedURL.absoluteString })
        let newFeeds = seedFeeds.filter { !existing.contains($0.feedURL.absoluteString) }
        feedStore.feeds.append(contentsOf: newFeeds)
        feedStore.persistFeeds(feedStore.feeds)
        addedFeeds.append("\(newFeeds.count) starter feeds loaded")
        starterPackLoaded = true
    }

    private func addFeed() {
        let input = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isAddingFeed = true
        feedError = nil

        Task {
            let result = await feedStore.addFeed(from: input)
            isAddingFeed = false
            switch result {
            case .success(let feed):
                addedFeeds.append(feed.name)
                feedURL = ""
            case .failure:
                feedError = "Couldn't find a feed at that URL. Try pasting a direct feed URL."
            }
        }
    }

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            let count = feedStore.importOPML(from: url)
            if count > 0 {
                addedFeeds.append("\(count) feeds imported from OPML")
            } else {
                feedError = "No new feeds found in that OPML file."
            }
        }
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

// MARK: - Onboarding Preset Row

private struct OnboardingPresetRow: View {
    let preset: TypographyPreset
    let isSelected: Bool
    var scale: Double = 1.0

    private var scaledSize: Double { max(9, 12 * scale) }
    private var scaledLabelSize: Double { max(10, 13 * scale) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.label)
                    .font(.system(size: scaledLabelSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text("The quick brown fox jumps over the lazy dog")
                    .font(sampleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: scale)
    }

    private var sampleFont: Font {
        let s = scaledSize
        switch preset {
        case .nightReader: return .system(size: s, design: .serif)
        case .newspaperClassic: return .custom("Charter", size: s)
        case .drudgeCondensed, .monoLedger: return .system(size: max(9, 11 * scale), design: .monospaced)
        case .minimalUtility, .compactPro: return .system(size: max(9, 11 * scale), design: .default)
        case .magazine: return .custom("SF Pro Display", size: s)
        case .metroWire: return .custom("Avenir Next", size: s)
        case .quietSerif: return .custom("Palatino", size: s)
        case .roundDeck: return .system(size: s, design: .rounded)
        }
    }
}
