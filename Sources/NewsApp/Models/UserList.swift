import Foundation

struct UserList: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var iconSystemName: String?
    var iconURL: URL?
    var feedIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        iconSystemName: String? = nil,
        iconURL: URL? = nil,
        feedIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.iconURL = iconURL
        self.feedIDs = feedIDs
    }
}
