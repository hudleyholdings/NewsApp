import Foundation

enum SidebarSelection: Hashable {
    case list(UUID)
    case feed(UUID)
    case category(String)
    // Radio
    case radioBrowse
    case radioStation(UUID)
    case radioCategory(RadioCategory)
    case radioFavorites

    var listID: UUID? {
        if case .list(let id) = self { return id }
        return nil
    }

    var feedID: UUID? {
        if case .feed(let id) = self { return id }
        return nil
    }

    var categoryName: String? {
        if case .category(let name) = self { return name }
        return nil
    }

    var radioStationID: UUID? {
        if case .radioStation(let id) = self { return id }
        return nil
    }
}
