import SwiftUI

struct RadioStationListView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var radioStore = RadioStore.shared
    @StateObject private var radioPlayer = RadioPlayer.shared
    /// Drives the Add Custom Station sheet via `.sheet(item:)` so SwiftUI is
    /// guaranteed to have a station to edit (or `nil` sentinel for add).
    @State private var stationSheetTarget: AddStationSheetTarget?

    var body: some View {
        VStack(spacing: 0) {
            addStationBar
            Divider()

            // Mini player bar if something is playing
            if let station = radioPlayer.currentStation {
                RadioMiniPlayer(station: station)
                Divider()
            }

            List(selection: Binding(
                get: { selectedStationID },
                set: { newID in
                    if let id = newID {
                        feedStore.selectedSidebarItem = .radioStation(id)
                    }
                }
            )) {
                ForEach(filteredStations) { station in
                    RadioStationListRow(
                        station: station,
                        distance: radioStore.formattedDistance(
                            for: station,
                            fromLat: settings.weatherLatitude,
                            lon: settings.weatherLongitude
                        ),
                        isSelected: selectedStationID == station.id,
                        isPlaying: radioPlayer.currentStation?.id == station.id && radioPlayer.isPlaying,
                        isFavorite: radioStore.isFavorite(station)
                    )
                    .tag(station.id)
                    .contextMenu {
                        Button {
                            if radioPlayer.currentStation?.id == station.id {
                                radioPlayer.togglePlayPause()
                            } else {
                                radioPlayer.play(station)
                            }
                        } label: {
                            Label(
                                radioPlayer.currentStation?.id == station.id && radioPlayer.isPlaying ? "Pause" : "Play",
                                systemImage: radioPlayer.currentStation?.id == station.id && radioPlayer.isPlaying ? "pause.fill" : "play.fill"
                            )
                        }

                        Divider()

                        Button {
                            radioStore.toggleFavorite(station)
                        } label: {
                            Label(
                                radioStore.isFavorite(station) ? "Remove from Favorites" : "Add to Favorites",
                                systemImage: radioStore.isFavorite(station) ? "star.slash" : "star"
                            )
                        }

                        if let website = station.website {
                            Divider()
                            Button {
                                NSWorkspace.shared.open(website)
                            } label: {
                                Label("Open Website", systemImage: "safari")
                            }
                        }

                        if station.isUserAdded {
                            Divider()
                            Button {
                                stationSheetTarget = .edit(station)
                            } label: {
                                Label("Edit Station…", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                radioStore.removeUserStation(station)
                            } label: {
                                Label("Delete Station", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .sheet(item: $stationSheetTarget) { target in
            AddRadioStationSheet(
                isPresented: Binding(
                    get: { stationSheetTarget != nil },
                    set: { if !$0 { stationSheetTarget = nil } }
                ),
                existing: target.station
            )
        }
        .overlay {
            if filteredStations.isEmpty {
                ContentUnavailableView(
                    "No Stations",
                    systemImage: "radio",
                    description: Text(emptyMessage)
                )
            }
        }
    }

    private var selectedStationID: UUID? {
        if case .radioStation(let id) = feedStore.selectedSidebarItem {
            return id
        }
        return nil
    }

    private var navigationTitle: String {
        guard let selection = feedStore.selectedSidebarItem else { return "Radio" }
        switch selection {
        case .radioBrowse:
            return "All Radio Stations"
        case .radioFavorites:
            return "Favorite Stations"
        case .radioUserStations:
            return "My Stations"
        case .radioCategory(let category):
            return category.displayName
        default:
            return "Radio"
        }
    }

    private var emptyMessage: String {
        if case .radioFavorites = feedStore.selectedSidebarItem {
            return "Star stations to add them to your favorites."
        }
        if case .radioUserStations = feedStore.selectedSidebarItem {
            return "Add a custom station with the + button above."
        }
        return "No stations available in this category."
    }

    private var baseStations: [RadioStation] {
        guard let selection = feedStore.selectedSidebarItem else { return radioStore.newsTalkStations }
        switch selection {
        case .radioBrowse:
            return radioStore.newsTalkStations
        case .radioFavorites:
            return radioStore.favoriteStations
        case .radioUserStations:
            return radioStore.userStations
        case .radioCategory(let category):
            // Only show if it's News/Talk
            if category == .newsTalk {
                return radioStore.groupedByCategory[category] ?? []
            }
            return []
        case .radioStation(let id):
            // Keep the middle column in context with the selected station: a custom
            // station shows the custom-stations list; otherwise the news/talk list.
            if radioStore.userStations.contains(where: { $0.id == id }) {
                return radioStore.userStations
            }
            return radioStore.newsTalkStations
        default:
            return []
        }
    }

    // MARK: - Add custom station

    /// Compact bar above the list with a primary "Add Custom Station" affordance.
    /// Visible in every radio view so a brand-new user (zero custom stations) can
    /// still discover the entry point.
    private var addStationBar: some View {
        HStack {
            Button {
                stationSheetTarget = .add
            } label: {
                Label("Add Custom Station", systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Add a station from a stream URL")
            Spacer()
            if !radioStore.userStations.isEmpty {
                Text("\(radioStore.userStations.count) custom")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Identifiable wrapper so `.sheet(item:)` can drive both Add and Edit through one
/// modifier. `.add` has no associated station; `.edit` carries the one to mutate.
private enum AddStationSheetTarget: Identifiable {
    case add
    case edit(RadioStation)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let station): return "edit-\(station.id.uuidString)"
        }
    }

    var station: RadioStation? {
        switch self {
        case .add: return nil
        case .edit(let s): return s
        }
    }
}

extension RadioStationListView {
    fileprivate var filteredStations: [RadioStation] {
        let query = feedStore.searchText
        guard !query.isEmpty else { return baseStations }
        return baseStations.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.genre.localizedCaseInsensitiveContains(query) ||
            $0.location.localizedCaseInsensitiveContains(query) ||
            $0.country.localizedCaseInsensitiveContains(query)
        }
    }
}

struct RadioStationListRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var radioPlayer = RadioPlayer.shared
    let station: RadioStation
    let distance: String?
    let isSelected: Bool
    let isPlaying: Bool
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Play indicator / icon
            ZStack {
                Circle()
                    .fill(isPlaying ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 44, height: 44)

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
                } else if radioPlayer.isBuffering && radioPlayer.currentStation?.id == station.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "radio.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .onTapGesture {
                if radioPlayer.currentStation?.id == station.id {
                    radioPlayer.togglePlayPause()
                } else {
                    radioPlayer.play(station)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(station.name)
                        .font(settings.listFont(size: settings.articleTitleSize, weight: .semibold))
                        .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                }

                HStack(spacing: 6) {
                    Text(station.genre)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    Text(station.location)
                    if let distance {
                        Text("•")
                        Text(distance)
                    }
                }
                .font(settings.listFont(size: settings.articleMetaSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if !station.description.isEmpty {
                    Text(station.description)
                        .font(settings.listFont(size: settings.articleSummarySize))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Bitrate/codec info
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(station.bitrate) kbps")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(station.codec)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

// MARK: - Mini Player

struct RadioMiniPlayer: View {
    @StateObject private var radioPlayer = RadioPlayer.shared
    let station: RadioStation

    var body: some View {
        HStack(spacing: 12) {
            // Station info
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(station.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Playback controls
            if radioPlayer.isBuffering {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    radioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: radioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Button {
                radioPlayer.stop()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Radio Player View (Detail Pane)

struct RadioPlayerView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var radioStore = RadioStore.shared
    @StateObject private var radioPlayer = RadioPlayer.shared
    let station: RadioStation

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Large station display
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 20, y: 10)

                    if radioPlayer.isPlaying && radioPlayer.currentStation?.id == station.id {
                        Image(systemName: "waveform")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
                    } else {
                        Image(systemName: "radio.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                    }
                }

                VStack(spacing: 8) {
                    Text(station.name)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Label(station.genre, systemImage: "music.note")
                        Text("•")
                        Label(station.location, systemImage: "mappin")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if !station.description.isEmpty {
                        Text(station.description)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                // Playback controls
                HStack(spacing: 32) {
                    Button {
                        radioStore.toggleFavorite(station)
                    } label: {
                        Image(systemName: radioStore.isFavorite(station) ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(radioStore.isFavorite(station) ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(radioStore.isFavorite(station) ? "Remove from Favorites" : "Add to Favorites")

                    Button {
                        if radioPlayer.currentStation?.id == station.id {
                            radioPlayer.togglePlayPause()
                        } else {
                            radioPlayer.play(station)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 64, height: 64)

                            if radioPlayer.isBuffering && radioPlayer.currentStation?.id == station.id {
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(.white)
                            } else {
                                Image(systemName: radioPlayer.currentStation?.id == station.id && radioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let website = station.website {
                        Button {
                            NSWorkspace.shared.open(website)
                        } label: {
                            Image(systemName: "safari")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open Website")
                    } else {
                        Color.clear.frame(width: 32, height: 32)
                    }
                }

                // Volume slider
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(radioPlayer.volume) },
                        set: { radioPlayer.setVolume(Float($0)) }
                    ), in: 0...1)
                    .frame(width: 200)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)
            }

            Spacer()

            // Footer with technical info
            Divider()
            HStack {
                HStack(spacing: 16) {
                    Label("\(station.bitrate) kbps", systemImage: "antenna.radiowaves.left.and.right")
                    Label(station.codec, systemImage: "waveform")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                Spacer()
                if !station.notes.isEmptyOrNil {
                    Text(station.notes ?? "")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool {
        self?.isEmpty ?? true
    }
}
