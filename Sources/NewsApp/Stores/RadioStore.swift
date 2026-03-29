import Foundation
import SwiftUI

@MainActor
final class RadioStore: ObservableObject {
    static let shared = RadioStore()

    @Published var stations: [RadioStation] = []
    @Published var favorites: Set<UUID> = []

    private let favoritesKey = "radioFavorites"

    private init() {
        loadStations()
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
}
