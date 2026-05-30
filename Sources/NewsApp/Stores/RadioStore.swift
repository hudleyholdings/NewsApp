import Foundation
import SwiftUI

@MainActor
final class RadioStore: ObservableObject {
    static let shared = RadioStore()

    @Published var stations: [RadioStation] = []
    @Published var favorites: Set<UUID> = []
    /// Stations the user has added via the in-app form. Persisted separately
    /// from `stations` so reloading the bundled CSV never wipes them.
    @Published private(set) var userStations: [RadioStation] = []

    private let favoritesKey = "radioFavorites"
    private let userStationsKey = "userRadioStations"

    private init() {
        loadStations()
        loadUserStations()
        loadFavorites()
    }

    var groupedByCategory: [RadioCategory: [RadioStation]] {
        Dictionary(grouping: stations.filter { $0.streamType != .aggregator },
                   by: { $0.category })
    }

    var sortedCategories: [RadioCategory] {
        groupedByCategory.keys.sorted { $0.displayName < $1.displayName }
    }

    var favoriteStations: [RadioStation] {
        stations.filter { favorites.contains($0.id) }
    }

    // News/Talk stations only (no music, religion, etc.)
    var newsTalkStations: [RadioStation] {
        stations.filter { $0.category == .newsTalk && $0.streamType != .aggregator }
    }

    func formattedDistance(for station: RadioStation, fromLat lat: Double, lon: Double) -> String? {
        guard station.hasValidCoordinates, lat != 0 || lon != 0 else { return nil }
        let km = station.distance(fromLat: lat, lon: lon)
        if km < 1000 {
            return "\(Int(km)) km"
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return (formatter.string(from: NSNumber(value: km)) ?? "\(Int(km))") + " km"
        }
    }

    // MARK: - Favorites

    func toggleFavorite(_ station: RadioStation) {
        if favorites.contains(station.id) {
            favorites.remove(station.id)
        } else {
            favorites.insert(station.id)
        }
        saveFavorites()
    }

    func isFavorite(_ station: RadioStation) -> Bool {
        favorites.contains(station.id)
    }

    // MARK: - Data Loading

    func loadStations() {
        guard let url = Bundle.module.url(forResource: "radio-stations", withExtension: "csv"),
              let data = try? String(contentsOf: url, encoding: .utf8) else {
            AppLogger.shared.log("RadioStore: Could not load radio-stations.csv")
            return
        }
        stations = parseCSV(data)
        AppLogger.shared.log("RadioStore: Loaded \(stations.count) stations")
    }

    private func parseCSV(_ data: String) -> [RadioStation] {
        var result: [RadioStation] = []
        let lines = data.components(separatedBy: .newlines)

        // Skip header
        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let fields = parseCSVLine(line)
            guard fields.count >= 13 else { continue }

            let categoryString = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let category = RadioCategory(rawValue: categoryString) ?? .aggregator

            let streamTypeString = fields[9].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let streamType = RadioStation.RadioStreamType(rawValue: streamTypeString) ?? .liveStream

            guard let streamURL = URL(string: fields[7].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) else { continue }

            let station = RadioStation(
                id: UUID(),
                name: fields[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                category: category,
                genre: fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                location: fields[3].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                country: fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                latitude: Double(fields[5]) ?? 0,
                longitude: Double(fields[6]) ?? 0,
                streamURL: streamURL,
                website: URL(string: fields[8].trimmingCharacters(in: CharacterSet(charactersIn: "\""))),
                streamType: streamType,
                bitrate: Int(fields[10]) ?? 128,
                codec: fields[11].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                description: fields[12].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                notes: fields.count > 13 ? fields[13].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : nil
            )
            result.append(station)
        }

        return result
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField)

        return fields
    }

    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            favorites = ids
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    // MARK: - User-added stations

    /// Add a new user station. Returns the created station so callers can
    /// immediately navigate to it / play it if they want.
    @discardableResult
    func addUserStation(
        name: String,
        streamURL: URL,
        category: RadioCategory,
        website: URL? = nil,
        description: String = ""
    ) -> RadioStation {
        let station = RadioStation(
            id: UUID(),
            name: name,
            category: category,
            genre: category.displayName,
            location: "",
            country: "",
            latitude: 0,
            longitude: 0,
            streamURL: streamURL,
            website: website,
            streamType: .liveStream,
            bitrate: 128,
            codec: "",
            description: description,
            notes: nil,
            isUserAdded: true
        )
        userStations.append(station)
        saveUserStations()
        rebuildStations()
        return station
    }

    /// Update an existing user station in place. No-op for bundled stations.
    func updateUserStation(_ station: RadioStation) {
        guard let index = userStations.firstIndex(where: { $0.id == station.id }) else { return }
        var updated = station
        updated.isUserAdded = true  // enforce — defends against external edits
        userStations[index] = updated
        saveUserStations()
        rebuildStations()
    }

    /// Remove a user station and tidy up references (favorites, current playback).
    func removeUserStation(_ station: RadioStation) {
        guard let index = userStations.firstIndex(where: { $0.id == station.id }) else { return }
        userStations.remove(at: index)
        if favorites.contains(station.id) {
            favorites.remove(station.id)
            saveFavorites()
        }
        saveUserStations()
        rebuildStations()
    }

    /// Combine bundled CSV stations with user-added ones. `loadStations()` puts
    /// the bundled set into `stations` directly; this re-applies the merge any
    /// time the user set changes.
    private func rebuildStations() {
        // The bundled stations are everything in `stations` minus any user-added
        // entries already there. Stripping & re-appending avoids duplicates if
        // this is called multiple times.
        let bundled = stations.filter { !$0.isUserAdded }
        stations = bundled + userStations
    }

    private func loadUserStations() {
        guard let data = UserDefaults.standard.data(forKey: userStationsKey),
              let decoded = try? JSONDecoder().decode([RadioStation].self, from: data) else {
            return
        }
        // Force the flag on for everything we load from this key — defensive in
        // case earlier data didn't include it.
        userStations = decoded.map { station in
            var copy = station
            copy.isUserAdded = true
            return copy
        }
        rebuildStations()
    }

    private func saveUserStations() {
        if let data = try? JSONEncoder().encode(userStations) {
            UserDefaults.standard.set(data, forKey: userStationsKey)
        }
    }
}
