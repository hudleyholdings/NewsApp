import Foundation

struct RadioStation: Identifiable, Hashable {
    let id: UUID
    let name: String
    let category: RadioCategory
    let genre: String
    let location: String
    let country: String
    let latitude: Double
    let longitude: Double
    let streamURL: URL
    let website: URL?
    let streamType: RadioStreamType
    let bitrate: Int
    let codec: String
    let description: String
    let notes: String?

    enum RadioStreamType: String {
        case liveStream = "live_stream"
        case aggregator = "aggregator"
    }

    var hasValidCoordinates: Bool {
        latitude != 0 || longitude != 0
    }

    func distance(fromLat lat: Double, lon: Double) -> Double {
        let earthRadius = 6371.0 // km
        let dLat = (latitude - lat) * .pi / 180
        let dLon = (longitude - lon) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat * .pi / 180) * cos(latitude * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return earthRadius * c
    }
}

enum RadioCategory: String, CaseIterable, Hashable {
    case newsTalk = "News/Talk"
    case music = "Music"
    case sports = "Sports"
    case aggregator = "Aggregator"

    var displayName: String {
        switch self {
        case .newsTalk: return "News & Talk"
        case .music: return "Music"
        case .sports: return "Sports"
        case .aggregator: return "Aggregator"
        }
    }

    var icon: String {
        switch self {
        case .newsTalk: return "mic.fill"
        case .music: return "music.note"
        case .sports: return "sportscourt.fill"
        case .aggregator: return "antenna.radiowaves.left.and.right"
        }
    }
}
