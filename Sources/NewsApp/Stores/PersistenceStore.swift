import Foundation

struct CacheStorageUsage: Equatable {
    var articleBytes: Int64
    var networkCacheBytes: Int64

    static let empty = CacheStorageUsage(articleBytes: 0, networkCacheBytes: 0)

    var totalBytes: Int64 {
        articleBytes + networkCacheBytes
    }
}

struct PersistenceStore {
    private let directoryURL: URL
    private let feedsURL: URL
    private let articlesURL: URL
    private let listsURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = baseURL.appendingPathComponent("NewsApp", isDirectory: true)
        feedsURL = directoryURL.appendingPathComponent("feeds.json")
        articlesURL = directoryURL.appendingPathComponent("articles.json")
        listsURL = directoryURL.appendingPathComponent("lists.json")
        createDirectoryIfNeeded()
    }

    func loadFeeds() -> [Feed]? {
        guard let data = try? Data(contentsOf: feedsURL) else { return nil }
        return try? JSONDecoder().decode([Feed].self, from: data)
    }

    func saveFeeds(_ feeds: [Feed]) {
        guard let data = try? JSONEncoder().encode(feeds) else { return }
        try? data.write(to: feedsURL, options: [.atomic])
    }

    func loadArticles() -> [Article]? {
        guard let data = try? Data(contentsOf: articlesURL) else { return nil }
        return try? JSONDecoder().decode([Article].self, from: data)
    }

    func saveArticles(_ articles: [Article]) {
        guard let data = try? JSONEncoder().encode(articles) else { return }
        try? data.write(to: articlesURL, options: [.atomic])
    }

    func loadLists() -> [UserList]? {
        guard let data = try? Data(contentsOf: listsURL) else { return nil }
        return try? JSONDecoder().decode([UserList].self, from: data)
    }

    func saveLists(_ lists: [UserList]) {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        try? data.write(to: listsURL, options: [.atomic])
    }

    func resetCache() {
        try? FileManager.default.removeItem(at: articlesURL)
    }

    func articleCacheSizeBytes() -> Int64 {
        allocatedFileSize(at: articlesURL)
    }

    private func createDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func allocatedFileSize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
            if let total = values.totalFileAllocatedSize {
                return Int64(total)
            }
            if let file = values.fileAllocatedSize {
                return Int64(file)
            }
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }
}
