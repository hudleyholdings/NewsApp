import Foundation

struct Article: Identifiable, Codable, Hashable {
    var id: UUID
    var feedID: UUID
    var externalID: String
    var title: String
    var summary: String?
    var contentHTML: String?
    var contentText: String?
    var readerHTML: String?
    var link: URL?
    var author: String?
    var publishedAt: Date?
    var imageURL: URL?
    var forceWebView: Bool?
    var isRead: Bool
    var isStarred: Bool
    var addedAt: Date

    init(
        id: UUID = UUID(),
        feedID: UUID,
        externalID: String,
        title: String,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        readerHTML: String? = nil,
        link: URL? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        imageURL: URL? = nil,
        forceWebView: Bool? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.feedID = feedID
        self.externalID = externalID
        self.title = title
        self.summary = summary
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.readerHTML = readerHTML
        self.link = link
        self.author = author
        self.publishedAt = publishedAt
        self.imageURL = imageURL
        self.forceWebView = forceWebView
        self.isRead = isRead
        self.isStarred = isStarred
        self.addedAt = addedAt
    }
}
