import Foundation
import SwiftUI

@MainActor
final class FeedStore: ObservableObject {
    static let allFeedsID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Published var feeds: [Feed] = []
    @Published var lists: [UserList] = []
    @Published var articlesByFeed: [UUID: [Article]] = [:] {
        didSet { invalidateArticleCache() }
    }
    @Published var selectedSidebarItem: SidebarSelection? = .list(FeedStore.allFeedsID) {
        didSet { markAllAsRead(for: selectedSidebarItem) }
    }
    @Published var selectedArticleID: UUID?
    @Published var isRefreshing: Bool = false
    @Published var statusMessage: String?
    @Published var searchText: String = ""
    private var readingProgressByArticle: [UUID: Double] = [:]

    /// Time when the app session started (for "new since session" badge mode)
    let sessionStartTime: Date = Date()
    /// Time of the last refresh (for "new since refresh" badge mode)
    @Published var lastRefreshTime: Date = Date()

    private let persistence = PersistenceStore()
    private let fetcher = FeedFetcher()
    private let discovery = FeedDiscovery()
    private let extractor = ReaderExtractor()
    private let opmlService = OPMLService()
    private let gdeltService = GDELTService()
    private let polymarketService = PolymarketService()
    private let logger = AppLogger.shared
    private var autoRefreshTask: Task<Void, Never>?
    private var hasLoaded = false
    private var sortedArticlesCache: [SidebarSelection: [Article]] = [:]
    private var articleIndex: [UUID: Article] = [:]
    private var isArticleIndexDirty = true
    private let persistenceQueue = DispatchQueue(label: "NewsApp.Persistence", qos: .utility)

    // Polymarket sort cache: [feedID: [sort: articles]]
    private var polymarketSortCache: [UUID: [PolymarketSort: [Article]]] = [:]
    @Published var polymarketLoadingFeedID: UUID?

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let timer = logger.begin("loadIfNeeded")
        logger.log("App launch: loading feeds and cache")

        // Load feeds first (fast, required for UI)
        if let savedFeeds = persistence.loadFeeds() {
            feeds = savedFeeds
            logger.log("Loaded feeds from disk count=\(feeds.count)")
        } else {
            feeds = []
            logger.log("First launch: no feeds")
        }

        if let savedLists = persistence.loadLists() {
            lists = savedLists
            normalizeLists()
        }

        // Load cached articles (show immediately - stale-while-revalidate)
        if let savedArticles = persistence.loadArticles() {
            articlesByFeed = Dictionary(grouping: savedArticles, by: { $0.feedID })
            logger.log("Loaded cached articles count=\(savedArticles.count)")
        }

        ensureSelectionValid()
        invalidateArticleCache()
        timer.end()

        // Clean up old articles in background (after UI is ready)
        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
            await MainActor.run {
                // Default to 30 days if setting not available
                let retentionDays = UserDefaults.standard.integer(forKey: "articleRetentionDays")
                self.cleanupOldArticles(retentionDays: retentionDays > 0 ? retentionDays : 30)
            }
        }

        // Start background refresh after showing cached content
        Task(priority: .utility) {
            // Small delay to let UI render first
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await refreshAllInBackground()
        }
    }

    /// Background refresh - less aggressive, doesn't block UI
    private func refreshAllInBackground() async {
        guard !isRefreshing else { return }

        // Only refresh feeds that are stale (haven't been updated in last 5 minutes)
        let staleThreshold: TimeInterval = 5 * 60
        let now = Date()

        let staleFeeds = feeds.enumerated().filter { _, feed in
            guard feed.isEnabled && canAttemptFetch(feed) else { return false }
            guard let lastFetch = feed.lastFetchedAt else { return true }
            return now.timeIntervalSince(lastFetch) > staleThreshold
        }

        guard !staleFeeds.isEmpty else {
            logger.log("Background refresh skipped - all feeds fresh")
            return
        }

        isRefreshing = true
        logger.log("Background refresh start stale=\(staleFeeds.count)")

        // Parallel fetch with controlled concurrency
        await withTaskGroup(of: Void.self) { group in
            let maxConcurrent = 6
            var iterator = staleFeeds.makeIterator()
            var active = 0

            func startNext() -> Bool {
                guard let (index, feed) = iterator.next() else { return false }
                active += 1
                group.addTask { [self] in
                    _ = await self.fetchSingleFeed(index: index, feed: feed)
                }
                return true
            }

            for _ in 0..<min(maxConcurrent, staleFeeds.count) {
                _ = startNext()
            }

            for await _ in group {
                active -= 1
                _ = startNext()
            }
        }

        persistFeeds(feeds)
        persistArticles(allArticles())
        isRefreshing = false
        logger.log("Background refresh complete")
    }

    func configureAutoRefresh(enabled: Bool, intervalMinutes: Int) {
        autoRefreshTask?.cancel()
        guard enabled else { return }

        let interval = UInt64(max(5, intervalMinutes) * 60)
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                await refreshAll()
            }
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let timer = logger.begin("refreshAll")
        logger.log("Refresh start feeds=\(feeds.count)")

        // Get feeds that can be fetched, prioritizing selected feed
        let selectedFeedID: UUID? = {
            if case .feed(let id) = selectedSidebarItem { return id }
            return nil
        }()

        let fetchableFeeds = feeds.enumerated().filter { _, feed in
            feed.isEnabled && canAttemptFetch(feed)
        }.sorted { a, b in
            // Prioritize selected feed
            if a.1.id == selectedFeedID { return true }
            if b.1.id == selectedFeedID { return false }
            // Then by last fetch time (older first)
            let aTime = a.1.lastFetchedAt ?? .distantPast
            let bTime = b.1.lastFetchedAt ?? .distantPast
            return aTime < bTime
        }

        let totalFeeds = fetchableFeeds.count
        var completedFeeds = 0

        // Parallel fetch with controlled concurrency (8 concurrent requests)
        await withTaskGroup(of: FeedFetchResult?.self) { group in
            let maxConcurrent = 8
            var feedIterator = fetchableFeeds.makeIterator()
            var activeTasks = 0

            // Helper to start a fetch task
            func startNextFetch() -> Bool {
                guard let (index, feed) = feedIterator.next() else { return false }
                activeTasks += 1
                group.addTask { [self] in
                    await self.fetchSingleFeed(index: index, feed: feed)
                }
                return true
            }

            // Start initial batch
            for _ in 0..<min(maxConcurrent, totalFeeds) {
                _ = startNextFetch()
            }

            // Process results and start new tasks as others complete
            for await result in group {
                activeTasks -= 1
                completedFeeds += 1

                // Update status with progress
                let progress = Int((Double(completedFeeds) / Double(max(1, totalFeeds))) * 100)
                statusMessage = "Refreshing... \(progress)%"

                // Start next task if available
                _ = startNextFetch()
            }
        }

        // Final persist
        persistFeeds(feeds)
        persistArticles(allArticles())

        isRefreshing = false
        statusMessage = nil
        lastRefreshTime = Date()
        timer.end()
        logger.log("Refresh finished count=\(completedFeeds)")
    }

    /// Fetch a single feed and update state immediately (progressive loading)
    private func fetchSingleFeed(index: Int, feed: Feed) async -> FeedFetchResult? {
        // Mark attempt time
        await MainActor.run {
            if index < feeds.count {
                feeds[index].lastAttemptAt = Date()
            }
        }

        do {
            let result: FeedUpdateResult
            switch feed.sourceKind {
            case .rss:
                result = try await fetchRSSFeed(feed: feed)
            case .gdelt:
                result = try await fetchGDELTFeed(feed: feed)
            case .polymarket:
                result = try await fetchPolymarketFeed(feed: feed)
            }

            // Update state on main actor immediately (progressive loading)
            await MainActor.run {
                if let idx = feeds.firstIndex(where: { $0.id == feed.id }) {
                    if let entries = result.entries {
                        let existing = articlesByFeed[feed.id] ?? []
                        let merged = merge(entries: entries, existing: existing, feed: feeds[idx])
                        articlesByFeed[feed.id] = merged
                        feeds[idx].lastUpdated = Date()
                    }
                    feeds[idx].etag = result.etag ?? feeds[idx].etag
                    feeds[idx].lastModified = result.lastModified ?? feeds[idx].lastModified
                    feeds[idx].lastFetchedAt = Date()
                    feeds[idx].failureCount = 0
                    if let iconURL = result.iconURL {
                        feeds[idx].iconURL = iconURL
                    }
                }
            }
            logger.log("Feed ok name=\(feed.name)")
            return nil
        } catch {
            await MainActor.run {
                if let idx = feeds.firstIndex(where: { $0.id == feed.id }) {
                    feeds[idx].failureCount += 1
                }
            }
            logger.error("Feed error name=\(feed.name) error=\(error.localizedDescription)")
            return nil
        }
    }

    private struct FeedUpdateResult {
        var entries: [FeedEntry]?
        var etag: String?
        var lastModified: String?
        var iconURL: URL?
    }

    private func fetchRSSFeed(feed: Feed) async throws -> FeedUpdateResult {
        let result = try await fetcher.fetchFeed(
            from: feed.feedURL,
            etag: feed.etag,
            lastModified: feed.lastModified
        )
        return FeedUpdateResult(
            entries: result.parseResult?.entries,
            etag: result.etag,
            lastModified: result.lastModified
        )
    }

    private func fetchGDELTFeed(feed: Feed) async throws -> FeedUpdateResult {
        guard let config = feed.gdeltConfig else {
            throw GDELTServiceError.invalidQuery
        }
        let entries = try await gdeltService.fetchEntries(config: config)
        return FeedUpdateResult(entries: entries)
    }

    private func fetchPolymarketFeed(feed: Feed) async throws -> FeedUpdateResult {
        guard let config = feed.polymarketConfig else {
            throw PolymarketServiceError.invalidConfig
        }
        let entries = try await polymarketService.fetchEntries(config: config)
        return FeedUpdateResult(entries: entries)
    }

    func refresh(feedID: UUID) async {
        guard let index = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        do {
            if !canAttemptFetch(feeds[index]) { return }
            feeds[index].lastAttemptAt = Date()
            switch feeds[index].sourceKind {
            case .rss:
                let result = try await fetcher.fetchFeed(
                    from: feeds[index].feedURL,
                    etag: feeds[index].etag,
                    lastModified: feeds[index].lastModified
                )
                if let parseResult = result.parseResult {
                    let existing = articlesByFeed[feeds[index].id] ?? []
                    let merged = merge(entries: parseResult.entries, existing: existing, feed: feeds[index])
                    articlesByFeed[feeds[index].id] = merged
                    feeds[index].lastUpdated = Date()
                }
                feeds[index].etag = result.etag ?? feeds[index].etag
                feeds[index].lastModified = result.lastModified ?? feeds[index].lastModified
                feeds[index].lastFetchedAt = Date()
                feeds[index].failureCount = 0
                logger.log("Feed refresh ok name=\(feeds[index].name) status=\(result.httpStatus) notModified=\(result.notModified)")
            case .gdelt:
                guard let config = feeds[index].gdeltConfig else {
                    throw GDELTServiceError.invalidQuery
                }
                let entries = try await gdeltService.fetchEntries(config: config)
                let existing = articlesByFeed[feeds[index].id] ?? []
                let merged = merge(entries: entries, existing: existing, feed: feeds[index])
                articlesByFeed[feeds[index].id] = merged
                feeds[index].lastUpdated = Date()
                feeds[index].lastFetchedAt = Date()
                feeds[index].failureCount = 0
                logger.log("GDELT refresh ok name=\(feeds[index].name) count=\(entries.count)")
            case .polymarket:
                guard let config = feeds[index].polymarketConfig else {
                    throw PolymarketServiceError.invalidConfig
                }
                let entries = try await polymarketService.fetchEntries(config: config)
                let existing = articlesByFeed[feeds[index].id] ?? []
                let merged = merge(entries: entries, existing: existing, feed: feeds[index])
                articlesByFeed[feeds[index].id] = merged
                feeds[index].lastUpdated = Date()
                feeds[index].lastFetchedAt = Date()
                feeds[index].failureCount = 0
                logger.log("Polymarket refresh ok name=\(feeds[index].name) count=\(entries.count)")
            }
        } catch {
            feeds[index].failureCount += 1
            logger.error("Feed refresh error name=\(feeds[index].name) error=\(error.localizedDescription)")
        }
        persistFeeds(feeds)
        persistArticles(allArticles())
    }

    func addFeed(from input: String) async -> Result<Feed, Error> {
        await addFeed(from: input, category: nil, listIDs: [])
    }

    func addFeed(from input: String, category: String?, listIDs: [UUID]) async -> Result<Feed, Error> {
        do {
            let discoveryResult = try await discovery.discover(from: input)
            let candidate = try await resolveBestFeed(from: discoveryResult.feeds)
            let normalizedCategory = normalizedCategory(category)
            if let index = feeds.firstIndex(where: { $0.feedURL == candidate.url }) {
                if let normalizedCategory {
                    feeds[index].category = normalizedCategory
                }
                let existing = feeds[index]
                assignFeed(existing.id, toLists: listIDs)
                persistFeeds(feeds)
                logger.log("Feed add skipped existing=\(existing.feedURL.absoluteString)")
                return .success(existing)
            }
            let feed = Feed(
                name: candidate.title,
                feedURL: candidate.url,
                siteURL: discoveryResult.siteURL,
                category: normalizedCategory
            )
            feeds.append(feed)
            persistFeeds(feeds)
            invalidateArticleCache()
            assignFeed(feed.id, toLists: listIDs)
            logger.log("Feed added url=\(candidate.url.absoluteString)")
            return .success(feed)
        } catch {
            logger.error("Feed add error input=\(input) error=\(error.localizedDescription)")
            return .failure(error)
        }
    }

    func addGDELTSource(name: String?, config: GDELTSourceConfig, category: String?, listIDs: [UUID]) -> Result<Feed, Error> {
        do {
            guard let query = gdeltService.buildQuery(config: config), !query.isEmpty else {
                throw GDELTServiceError.invalidQuery
            }
            let displayName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = displayName?.isEmpty == false ? displayName! : "GDELT: \(query)"
            let normalizedCategory = normalizedCategory(category)
            if let index = feeds.firstIndex(where: { $0.sourceKind == .gdelt && $0.gdeltConfig == config }) {
                if let normalizedCategory {
                    feeds[index].category = normalizedCategory
                }
                let existing = feeds[index]
                assignFeed(existing.id, toLists: listIDs)
                persistFeeds(feeds)
                logger.log("GDELT add skipped existing=\(existing.name)")
                return .success(existing)
            }
            let url = gdeltService.sourceURL(config: config) ?? URL(string: "https://api.gdeltproject.org/api/v2/doc/doc")!
            let feed = Feed(
                name: resolvedName,
                feedURL: url,
                siteURL: nil,
                category: normalizedCategory,
                country: config.country?.uppercased(),
                sourceKind: .gdelt,
                gdeltConfig: config
            )
            feeds.append(feed)
            persistFeeds(feeds)
            invalidateArticleCache()
            assignFeed(feed.id, toLists: listIDs)
            logger.log("GDELT source added name=\(resolvedName)")
            return .success(feed)
        } catch {
            logger.error("GDELT source add error name=\(name ?? "") error=\(error.localizedDescription)")
            return .failure(error)
        }
    }

    func addPolymarketSource(name: String?, config: PolymarketSourceConfig, category: String?, listIDs: [UUID]) -> Result<Feed, Error> {
        let displayName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = normalizedCategory(category)
        let resolvedName = displayName?.isEmpty == false ? displayName! : "Polymarket: \(config.category.label) (\(config.sort.label))"

        if let index = feeds.firstIndex(where: { $0.sourceKind == .polymarket && $0.polymarketConfig == config }) {
            if let normalizedCategory {
                feeds[index].category = normalizedCategory
            }
            let existing = feeds[index]
            assignFeed(existing.id, toLists: listIDs)
            persistFeeds(feeds)
            logger.log("Polymarket add skipped existing=\(existing.name)")
            return .success(existing)
        }

        let url = polymarketService.sourceURL(config: config) ?? URL(string: "https://polymarket.com")!
        let feed = Feed(
            name: resolvedName,
            feedURL: url,
            siteURL: URL(string: "https://polymarket.com"),
            category: normalizedCategory,
            sourceKind: .polymarket,
            polymarketConfig: config,
            iconURL: URL(string: "https://polymarket.com/favicon.ico")
        )
        feeds.append(feed)
        persistFeeds(feeds)
        invalidateArticleCache()
        assignFeed(feed.id, toLists: listIDs)
        logger.log("Polymarket source added name=\(resolvedName)")
        return .success(feed)
    }

    func updatePolymarketSort(feedID: UUID, sort: PolymarketSort) {
        guard let index = feeds.firstIndex(where: { $0.id == feedID }),
              var config = feeds[index].polymarketConfig else { return }

        let oldSort = config.sort
        guard oldSort != sort else { return }

        // Cache current articles before switching
        if let currentArticles = articlesByFeed[feedID], !currentArticles.isEmpty {
            if polymarketSortCache[feedID] == nil {
                polymarketSortCache[feedID] = [:]
            }
            polymarketSortCache[feedID]?[oldSort] = currentArticles
        }

        // Update config synchronously
        config.sort = sort
        feeds[index].polymarketConfig = config

        // Check cache FIRST and update UI immediately
        if let cachedArticles = polymarketSortCache[feedID]?[sort], !cachedArticles.isEmpty {
            articlesByFeed[feedID] = cachedArticles
            logger.log("Polymarket cache hit sort=\(sort.rawValue) count=\(cachedArticles.count)")
        }

        // Persist and fetch in background (don't block UI)
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            await MainActor.run {
                self.persistFeeds(self.feeds)
            }
        }

        // Fetch fresh data in background
        Task(priority: .userInitiated) {
            await refreshPolymarketFast(feedID: feedID, sort: sort)
        }
    }

    /// Fast Polymarket refresh - minimal overhead
    private func refreshPolymarketFast(feedID: UUID, sort: PolymarketSort) async {
        guard let index = feeds.firstIndex(where: { $0.id == feedID }),
              let config = feeds[index].polymarketConfig else { return }

        // Show loading only if no cached data
        let hasCachedData = polymarketSortCache[feedID]?[sort]?.isEmpty == false
        if !hasCachedData {
            polymarketLoadingFeedID = feedID
        }

        do {
            let entries = try await polymarketService.fetchEntries(config: config)
            let newArticles = entries.map { entry in
                Article(
                    feedID: feedID,
                    externalID: entry.externalID,
                    title: entry.title,
                    summary: entry.summary,
                    contentHTML: entry.contentHTML,
                    link: entry.link.flatMap { URL(string: $0) },
                    author: entry.author,
                    publishedAt: entry.publishedAt,
                    imageURL: entry.imageURL.flatMap { URL(string: $0) }
                )
            }

            // Update cache and UI
            if polymarketSortCache[feedID] == nil {
                polymarketSortCache[feedID] = [:]
            }
            polymarketSortCache[feedID]?[sort] = newArticles
            articlesByFeed[feedID] = newArticles
        } catch {
            logger.error("Polymarket refresh failed: \(error)")
        }

        polymarketLoadingFeedID = nil
    }

    /// Quick refresh for Polymarket - used by refresh button
    func refreshPolymarketQuick(feedID: UUID) {
        guard let index = feeds.firstIndex(where: { $0.id == feedID }),
              let config = feeds[index].polymarketConfig else { return }

        polymarketLoadingFeedID = feedID

        Task(priority: .userInitiated) {
            await refreshPolymarketFast(feedID: feedID, sort: config.sort)
        }
    }

    func polymarketFeed(for feedID: UUID) -> Feed? {
        feeds.first { $0.id == feedID && $0.sourceKind == .polymarket }
    }

    func removeFeeds(at offsets: IndexSet) {
        let ids = offsets.map { feeds[$0].id }
        feeds.remove(atOffsets: offsets)
        ids.forEach { articlesByFeed[$0] = nil }
        if !lists.isEmpty {
            lists = lists.map { list in
                var updated = list
                updated.feedIDs.removeAll { ids.contains($0) }
                return updated
            }
            persistLists(lists)
            invalidateArticleCache()
        }
        persistFeeds(feeds)
        persistArticles(allArticles())
        if let selection = selectedSidebarItem, case .feed(let selectedID) = selection, ids.contains(selectedID) {
            selectedSidebarItem = .list(FeedStore.allFeedsID)
        }
        logger.log("Feeds removed count=\(offsets.count)")
    }

    func toggleFeedEnabled(_ feed: Feed) {
        guard let index = feeds.firstIndex(of: feed) else { return }
        feeds[index].isEnabled.toggle()
        persistFeeds(feeds)
        logger.log("Feed toggled name=\(feeds[index].name) enabled=\(feeds[index].isEnabled)")
    }

    func updateFeed(_ feed: Feed) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[index] = feed
        persistFeeds(feeds)
        invalidateArticleCache()
        logger.log("Feed updated name=\(feed.name)")
    }

    func deleteFeed(id: UUID) {
        guard let index = feeds.firstIndex(where: { $0.id == id }) else { return }
        let name = feeds[index].name
        feeds.remove(at: index)
        articlesByFeed.removeValue(forKey: id)
        // Remove from all lists
        for i in lists.indices {
            lists[i].feedIDs.removeAll { $0 == id }
        }
        persistFeeds(feeds)
        persistLists(lists)
        persistArticles(allArticles())
        invalidateArticleCache()
        if case .feed(let selectedID) = selectedSidebarItem, selectedID == id {
            selectedSidebarItem = .list(FeedStore.allFeedsID)
        }
        logger.log("Feed deleted name=\(name)")
    }

    func allCategories() -> [String] {
        let categories = Set(feeds.compactMap { $0.category })
        return categories.sorted()
    }

    func markRead(_ article: Article, isRead: Bool = true) {
        guard var list = articlesByFeed[article.feedID],
              let index = list.firstIndex(where: { $0.id == article.id }) else { return }
        list[index].isRead = isRead
        articlesByFeed[article.feedID] = list
        persistArticles(allArticles())
    }

    func toggleStar(_ article: Article) {
        guard var list = articlesByFeed[article.feedID],
              let index = list.firstIndex(where: { $0.id == article.id }) else { return }
        list[index].isStarred.toggle()
        articlesByFeed[article.feedID] = list
        persistArticles(allArticles())
    }

    func addList(name: String, iconSystemName: String?, iconURL: URL?, feedIDs: [UUID]) -> UserList {
        let list = UserList(name: name, iconSystemName: iconSystemName, iconURL: iconURL, feedIDs: feedIDs)
        lists.append(list)
        persistLists(lists)
        invalidateArticleCache()
        return list
    }

    func updateList(_ list: UserList) {
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[index] = list
        persistLists(lists)
        invalidateArticleCache()
    }

    func removeLists(at offsets: IndexSet) {
        let ids = offsets.map { lists[$0].id }
        lists.remove(atOffsets: offsets)
        persistLists(lists)
        invalidateArticleCache()
        if let selection = selectedSidebarItem, case .list(let selectedID) = selection, ids.contains(selectedID) {
            selectedSidebarItem = .list(FeedStore.allFeedsID)
        }
    }

    func addFeed(_ feedID: UUID, toList listID: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        if lists[index].feedIDs.contains(feedID) { return }
        lists[index].feedIDs.append(feedID)
        persistLists(lists)
        invalidateArticleCache()
    }

    func removeFeed(_ feedID: UUID, fromList listID: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[index].feedIDs.removeAll { $0 == feedID }
        persistLists(lists)
        invalidateArticleCache()
    }

    func clearCache() {
        articlesByFeed = [:]
        persistence.resetCache()
        logger.log("Cache cleared")
    }

    /// Mark all articles as read for a specific selection
    func markAllAsRead(for selection: SidebarSelection?) {
        let articlesToMark = articles(for: selection)
        var updatedCount = 0

        for article in articlesToMark where !article.isRead {
            if var list = articlesByFeed[article.feedID],
               let index = list.firstIndex(where: { $0.id == article.id }) {
                list[index].isRead = true
                articlesByFeed[article.feedID] = list
                updatedCount += 1
            }
        }

        if updatedCount > 0 {
            persistArticles(allArticles())
            invalidateArticleCache()
            logger.log("Marked all read count=\(updatedCount)")
        }
    }

    /// Clean up old articles based on retention period (preserves starred articles)
    func cleanupOldArticles(retentionDays: Int) {
        guard retentionDays > 0 else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        var totalRemoved = 0

        for (feedID, articles) in articlesByFeed {
            let filtered = articles.filter { article in
                // Always keep starred articles
                if article.isStarred { return true }
                // Keep articles newer than cutoff
                let articleDate = article.publishedAt ?? article.addedAt
                return articleDate > cutoffDate
            }

            let removed = articles.count - filtered.count
            if removed > 0 {
                articlesByFeed[feedID] = filtered
                totalRemoved += removed
            }
        }

        if totalRemoved > 0 {
            persistArticles(allArticles())
            invalidateArticleCache()
            logger.log("Cleanup removed old articles count=\(totalRemoved) cutoff=\(retentionDays) days")
        }
    }

    func importOPML(from url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        let imported = opmlService.parse(data: data)
        guard !imported.isEmpty else { return 0 }

        var added = 0
        let existing = Set(feeds.map { $0.feedURL.absoluteString })
        for feed in imported where !existing.contains(feed.xmlURL.absoluteString) {
            let newFeed = Feed(name: feed.title, feedURL: feed.xmlURL, siteURL: feed.htmlURL)
            feeds.append(newFeed)
            added += 1
        }
        persistFeeds(feeds)
        invalidateArticleCache()
        logger.log("OPML import added=\(added)")
        return added
    }

    func exportOPML(to url: URL) -> Bool {
        let data = opmlService.export(feeds: feeds)
        do {
            try data.write(to: url, options: [.atomic])
            logger.log("OPML export url=\(url.absoluteString)")
            return true
        } catch {
            logger.error("OPML export error url=\(url.absoluteString)")
            return false
        }
    }

    func article(for id: UUID?) -> Article? {
        guard let id = id else { return nil }
        if isArticleIndexDirty {
            rebuildArticleIndex()
        }
        return articleIndex[id]
    }

    func readingProgress(for articleID: UUID) -> Double {
        readingProgressByArticle[articleID] ?? 0
    }

    func updateReadingProgress(for articleID: UUID, progress: Double) {
        readingProgressByArticle[articleID] = min(max(progress, 0), 1)
    }

    func articles(for selection: SidebarSelection?) -> [Article] {
        guard let selection = selection else { return allArticles() }
        switch selection {
        case .list(let id):
            return articlesForList(id)
        case .feed(let id):
            return articlesByFeed[id] ?? []
        case .category(let name):
            return articlesForCategory(name)
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites:
            return []
        }
    }

    func sortedArticles(for selection: SidebarSelection?) -> [Article] {
        let key = selection ?? .list(FeedStore.allFeedsID)
        if let cached = sortedArticlesCache[key] {
            return cached
        }
        let base = articles(for: selection)
        let sorted: [Article]
        switch selection {
        case .feed:
            sorted = base
        default:
            // Sort by published date (newest first). Articles without publishedAt go to the bottom.
            sorted = base.sorted { a, b in
                switch (a.publishedAt, b.publishedAt) {
                case let (aDate?, bDate?):
                    return aDate > bDate
                case (_?, nil):
                    return true  // a has date, b doesn't -> a comes first
                case (nil, _?):
                    return false // b has date, a doesn't -> b comes first
                case (nil, nil):
                    return a.addedAt > b.addedAt // Both missing: fallback to addedAt
                }
            }
        }
        sortedArticlesCache[key] = sorted
        return sorted
    }

    func articlesForCategory(_ category: String) -> [Article] {
        let feedsInCategory = feeds.filter { ($0.category ?? "Other") == category }
        let feedIDs = Set(feedsInCategory.map { $0.id })
        return articlesByFeed
            .filter { feedIDs.contains($0.key) }
            .flatMap { $0.value }
    }

    func categoryUnreadCount(for category: String) -> Int {
        articlesForCategory(category).filter { !$0.isRead }.count
    }

    // MARK: - Badge Count Methods

    /// Get the badge count for a selection based on the specified mode
    func badgeCount(for selection: SidebarSelection?, mode: BadgeCountMode) -> Int {
        let articlesForSelection = articles(for: selection)
        switch mode {
        case .unread:
            return articlesForSelection.filter { !$0.isRead }.count
        case .newSinceSession:
            return articlesForSelection.filter { !$0.isRead && $0.addedAt > sessionStartTime }.count
        case .newSinceRefresh:
            return articlesForSelection.filter { !$0.isRead && $0.addedAt > lastRefreshTime }.count
        }
    }

    /// Get the badge count for a feed based on the specified mode
    func feedBadgeCount(for feedID: UUID, mode: BadgeCountMode) -> Int {
        let feedArticles = articlesByFeed[feedID] ?? []
        switch mode {
        case .unread:
            return feedArticles.filter { !$0.isRead }.count
        case .newSinceSession:
            return feedArticles.filter { !$0.isRead && $0.addedAt > sessionStartTime }.count
        case .newSinceRefresh:
            return feedArticles.filter { !$0.isRead && $0.addedAt > lastRefreshTime }.count
        }
    }

    /// Get the badge count for a category based on the specified mode
    func categoryBadgeCount(for category: String, mode: BadgeCountMode) -> Int {
        badgeCount(for: .category(category), mode: mode)
    }

    /// Get the badge count for a list based on the specified mode
    func listBadgeCount(for listID: UUID, mode: BadgeCountMode) -> Int {
        badgeCount(for: .list(listID), mode: mode)
    }

    func favoritesArticles() -> [Article] {
        allArticles().filter { $0.isStarred }
    }

    func listName(for id: UUID) -> String? {
        if id == FeedStore.allFeedsID {
            return "All Feeds"
        }
        if id == FeedStore.favoritesID {
            return "Bookmarks"
        }
        return lists.first(where: { $0.id == id })?.name
    }

    func listUnreadCount(for id: UUID) -> Int {
        articlesForList(id).filter { !$0.isRead }.count
    }

    func feedName(for id: UUID) -> String? {
        feeds.first(where: { $0.id == id })?.name
    }

    func feedCategory(for id: UUID) -> String? {
        feeds.first(where: { $0.id == id })?.category
    }

    // MARK: - Keyboard Navigation Helpers

    /// Returns a flat ordered list of sidebar items matching the visual sidebar order
    func orderedSidebarItems(radioEnabled: Bool, hasLocation: Bool, hasRadioFavorites: Bool) -> [SidebarSelection] {
        var items: [SidebarSelection] = []

        // Lists section
        items.append(.list(FeedStore.allFeedsID))
        items.append(.list(FeedStore.favoritesID))
        for list in lists {
            items.append(.list(list.id))
        }

        // Categories + Feeds (sorted same as FeedListView)
        let grouped = Dictionary(grouping: feeds, by: { $0.category ?? "Other" })
        let sortedCats = grouped.keys.sorted { cat1, cat2 in
            let isSports1 = cat1.lowercased().contains("sport")
            let isSports2 = cat2.lowercased().contains("sport")
            if isSports1 && !isSports2 { return false }
            if !isSports1 && isSports2 { return true }
            return cat1 < cat2
        }
        for category in sortedCats {
            items.append(.category(category))
            let feedsInCat = (grouped[category] ?? []).sorted { $0.name < $1.name }
            for feed in feedsInCat {
                items.append(.feed(feed.id))
            }
        }

        // Radio section
        if radioEnabled {
            items.append(.radioBrowse)
            if hasRadioFavorites { items.append(.radioFavorites) }
        }

        return items
    }

    /// Navigate to prev/next sidebar item
    func navigateSidebar(direction: Int, radioEnabled: Bool, hasLocation: Bool, hasRadioFavorites: Bool) {
        let items = orderedSidebarItems(radioEnabled: radioEnabled, hasLocation: hasLocation, hasRadioFavorites: hasRadioFavorites)
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex(of: selectedSidebarItem ?? .list(FeedStore.allFeedsID)) ?? 0
        let newIndex = max(0, min(items.count - 1, currentIndex + direction))
        selectedSidebarItem = items[newIndex]
        selectedArticleID = nil
    }

    /// Navigate to prev/next article in current list
    func navigateArticle(direction: Int) {
        let articles = filteredSortedArticles()
        guard !articles.isEmpty else { return }
        if let currentID = selectedArticleID,
           let currentIndex = articles.firstIndex(where: { $0.id == currentID }) {
            let newIndex = max(0, min(articles.count - 1, currentIndex + direction))
            selectedArticleID = articles[newIndex].id
        } else {
            // No selection: pick first or last depending on direction
            selectedArticleID = direction > 0 ? articles.first?.id : articles.last?.id
        }
    }

    /// Articles filtered by search text, matching what ContentListView shows
    func filteredSortedArticles() -> [Article] {
        let base = sortedArticles(for: selectedSidebarItem)
        if searchText.isEmpty { return base }
        let query = searchText.lowercased()
        return base.filter {
            $0.title.lowercased().contains(query)
            || ($0.summary?.lowercased().contains(query) ?? false)
            || ($0.author?.lowercased().contains(query) ?? false)
        }
    }

    /// Open current article's link in the default browser
    func openCurrentArticleInBrowser() {
        guard let article = article(for: selectedArticleID),
              let url = article.link else { return }
        NSWorkspace.shared.open(url)
    }

    /// Toggle star on the currently selected article
    func toggleStarCurrentArticle() {
        guard let article = article(for: selectedArticleID) else { return }
        toggleStar(article)
    }

    /// Toggle read/unread on the currently selected article
    func toggleReadCurrentArticle() {
        guard let article = article(for: selectedArticleID) else { return }
        markRead(article, isRead: !article.isRead)
    }

    func allArticles() -> [Article] {
        articlesByFeed.values.flatMap { $0 }
    }

    func ensureContent(for articleID: UUID) async {
        guard let article = article(for: articleID), article.contentText == nil else { return }
        if let html = article.contentHTML, !html.isEmpty {
            let cleaned = ReaderCleaner.clean(html.strippingHTML())
            updateArticle(articleID: articleID, contentText: cleaned, imageURL: article.imageURL)
            return
        }
        guard let link = article.link else { return }

        // Skip reader extraction for known media/image URLs
        if isLikelyMediaURL(link) {
            updateArticle(articleID: articleID, contentText: nil, imageURL: article.imageURL, readerHTML: nil, forceWebView: true)
            logger.log("Reader extraction skipped media url=\(link.absoluteString)")
            return
        }

        do {
            let document = try await fetchDocument(url: link)
            if let mimeType = document.mimeType, !isLikelyHTML(mimeType: mimeType) {
                updateArticle(articleID: articleID, contentText: nil, imageURL: article.imageURL, readerHTML: nil, forceWebView: true)
                logger.log("Reader extraction skipped non-html url=\(link.absoluteString) mime=\(mimeType)")
                return
            }
            let readerContent = try extractor.extract(from: document.text, baseURL: link)
            updateArticle(articleID: articleID, contentText: readerContent.text, imageURL: readerContent.leadImageURL, readerHTML: readerContent.contentHTML, forceWebView: false)
            logger.log("Reader extraction ok url=\(link.absoluteString)")
        } catch {
            logger.error("Reader extraction error url=\(link.absoluteString)")
            return
        }
    }

    func updateArticle(articleID: UUID, contentText: String?, imageURL: URL?, readerHTML: String? = nil, forceWebView: Bool? = nil) {
        for (feedID, list) in articlesByFeed {
            if let index = list.firstIndex(where: { $0.id == articleID }) {
                var updated = list[index]
                if let contentText = contentText, !contentText.isEmpty {
                    updated.contentText = contentText
                }
                if let imageURL = imageURL {
                    updated.imageURL = imageURL
                }
                if let readerHTML = readerHTML, !readerHTML.isEmpty {
                    updated.readerHTML = readerHTML
                }
                if let forceWebView = forceWebView {
                    updated.forceWebView = forceWebView
                }
                var newList = list
                newList[index] = updated
                articlesByFeed[feedID] = newList
                persistArticles(allArticles())
                return
            }
        }
    }

    /// Discover og:image for articles that are missing images.
    /// Fetches article pages concurrently (up to 6 at a time) and updates the model.
    func discoverImages(for articles: [Article]) async {
        let missing = articles.filter { $0.imageURL == nil && $0.link != nil && !isLikelyMediaURL($0.link!) }
        guard !missing.isEmpty else { return }

        await withTaskGroup(of: (UUID, URL?).self) { group in
            var launched = 0
            for article in missing.prefix(30) {
                guard let link = article.link else { continue }
                launched += 1
                if launched > 6 {
                    // Wait for one to finish before launching more
                    if let result = await group.next(), let url = result.1 {
                        await MainActor.run { updateArticle(articleID: result.0, contentText: nil, imageURL: url) }
                    }
                }
                group.addTask { [weak self] in
                    guard let self else { return (article.id, nil) }
                    do {
                        let doc = try await self.fetchDocument(url: link)
                        let imageURL = ReaderExtractor.extractOGImage(from: doc.text, baseURL: link)
                        return (article.id, imageURL)
                    } catch {
                        return (article.id, nil)
                    }
                }
            }
            for await result in group {
                if let url = result.1 {
                    await MainActor.run { updateArticle(articleID: result.0, contentText: nil, imageURL: url) }
                }
            }
        }
    }

    private func merge(entries: [FeedEntry], existing: [Article], feed: Feed) -> [Article] {
        var list = existing
        var lookup: [String: Int] = [:]
        for (index, article) in list.enumerated() {
            lookup[article.externalID] = index
            if let link = article.link?.absoluteString {
                lookup[link] = index
            }
        }

        for entry in entries {
            let key = entry.externalID
            if let index = lookup[key] {
                var existing = list[index]
                if existing.summary == nil { existing.summary = entry.summary?.strippingHTML() }
                if existing.contentHTML == nil { existing.contentHTML = entry.contentHTML }
                if existing.author == nil { existing.author = entry.author }
                if existing.publishedAt == nil { existing.publishedAt = entry.publishedAt }
                if existing.link == nil, let link = entry.link { existing.link = URL(string: link) }
                if existing.imageURL == nil, let image = entry.imageURL { existing.imageURL = URL(string: image) }
                list[index] = existing
            } else {
                let article = Article(
                    feedID: feed.id,
                    externalID: entry.externalID,
                    title: entry.title.decodingHTMLEntities(),
                    summary: entry.summary?.strippingHTML(),
                    contentHTML: entry.contentHTML,
                    link: entry.link.flatMap { URL(string: $0) },
                    author: entry.author,
                    publishedAt: entry.publishedAt,
                    imageURL: entry.imageURL.flatMap { URL(string: $0) },
                    isRead: false
                )
                list.append(article)
                lookup[entry.externalID] = list.count - 1
            }
        }

        list.sort { ($0.publishedAt ?? $0.addedAt) > ($1.publishedAt ?? $1.addedAt) }
        // Cap at 500 articles per feed, but always keep starred ones
        if list.count > 500 {
            let starred = list.filter { $0.isStarred }
            let unstarred = list.filter { !$0.isStarred }.prefix(500 - starred.count)
            list = starred + unstarred
            list.sort { ($0.publishedAt ?? $0.addedAt) > ($1.publishedAt ?? $1.addedAt) }
        }
        return list
    }

    private func resolveBestFeed(from feeds: [DiscoveredFeed]) async throws -> DiscoveredFeed {
        for candidate in feeds {
            do {
                _ = try await fetcher.fetchFeed(from: candidate.url, etag: nil, lastModified: nil)
                return candidate
            } catch {
                continue
            }
        }
        throw URLError(.cannotParseResponse)
    }

    private func canAttemptFetch(_ feed: Feed) -> Bool {
        let now = Date()
        if let lastAttemptAt = feed.lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < 45 {
            return false
        }
        guard feed.failureCount > 0 else { return true }
        guard let lastAttemptAt = feed.lastAttemptAt else { return true }
        let backoffSeconds = min(3600.0, 30.0 * pow(2.0, Double(min(feed.failureCount, 6))))
        return now.timeIntervalSince(lastAttemptAt) >= backoffSeconds
    }

    func loadSeedFeeds() -> [Feed] {
        guard let url = Bundle.module.url(forResource: "feeds_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seedFeeds = try? JSONDecoder().decode([SeedFeed].self, from: data) else {
            return []
        }

        return seedFeeds.compactMap { seed in
            guard let feedURL = URL(string: seed.feed_url) else { return nil }
            return Feed(
                name: seed.name,
                feedURL: feedURL,
                siteURL: URL(string: seed.site),
                category: seed.category,
                country: seed.country
            )
        }
    }

    private func fetchDocument(url: URL) async throws -> FetchedDocument {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("NewsApp/1.0 (macOS; RSS Reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let mimeType = (response as? HTTPURLResponse)?.mimeType
        return FetchedDocument(text: String(decoding: data, as: UTF8.self), mimeType: mimeType)
    }

    private func isLikelyHTML(mimeType: String) -> Bool {
        let lower = mimeType.lowercased()
        if lower.contains("html") { return true }
        if lower.hasPrefix("text/") { return true }
        if lower.contains("xml") { return true }
        return false
    }

    private func isLikelyMediaURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let host = url.host?.lowercased() ?? ""

        // Common image extensions
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif", ".svg", ".bmp", ".ico"]
        for ext in imageExtensions {
            if path.hasSuffix(ext) { return true }
        }

        // Common video extensions
        let videoExtensions = [".mp4", ".webm", ".mov", ".avi", ".mkv", ".m4v"]
        for ext in videoExtensions {
            if path.hasSuffix(ext) { return true }
        }

        // Reddit media domains
        let mediaHosts = ["i.redd.it", "v.redd.it", "preview.redd.it", "i.imgur.com", "imgur.com/a/", "gfycat.com", "redgifs.com", "streamable.com"]
        for mediaHost in mediaHosts {
            if host.contains(mediaHost) || url.absoluteString.contains(mediaHost) { return true }
        }

        // Reddit media redirect URL
        if host == "www.reddit.com" && path == "/media" { return true }

        return false
    }

    private func normalizedCategory(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func assignFeed(_ feedID: UUID, toLists listIDs: [UUID]) {
        guard !listIDs.isEmpty else { return }
        for listID in listIDs {
            addFeed(feedID, toList: listID)
        }
    }

    private func articlesForList(_ id: UUID) -> [Article] {
        if id == FeedStore.allFeedsID {
            return allArticles()
        }
        if id == FeedStore.favoritesID {
            return favoritesArticles()
        }
        guard let list = lists.first(where: { $0.id == id }) else { return [] }
        let selected = Set(list.feedIDs)
        guard !selected.isEmpty else { return [] }
        return articlesByFeed
            .filter { selected.contains($0.key) }
            .flatMap { $0.value }
    }

    private func normalizeLists() {
        guard !lists.isEmpty else { return }
        let feedIDs = Set(feeds.map { $0.id })
        let updated = lists.map { list -> UserList in
            var newList = list
            newList.feedIDs = list.feedIDs.filter { feedIDs.contains($0) }
            return newList
        }
        if updated != lists {
            lists = updated
            persistLists(lists)
            invalidateArticleCache()
        }
    }

    func persistFeeds(_ feeds: [Feed]) {
        let persistence = persistence
        persistenceQueue.async {
            persistence.saveFeeds(feeds)
        }
    }

    private func persistLists(_ lists: [UserList]) {
        let persistence = persistence
        persistenceQueue.async {
            persistence.saveLists(lists)
        }
    }

    private func persistArticles(_ articles: [Article]) {
        let persistence = persistence
        persistenceQueue.async {
            persistence.saveArticles(articles)
        }
    }

    private func invalidateArticleCache() {
        sortedArticlesCache.removeAll(keepingCapacity: true)
        isArticleIndexDirty = true
    }

    private func rebuildArticleIndex() {
        let timer = logger.begin("rebuildArticleIndex")
        let items = allArticles()
        articleIndex = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        isArticleIndexDirty = false
        timer.end()
    }

    private func ensureSelectionValid() {
        guard let selection = selectedSidebarItem else {
            selectedSidebarItem = .list(FeedStore.allFeedsID)
            return
        }
        switch selection {
        case .feed(let id):
            if !feeds.contains(where: { $0.id == id }) {
                selectedSidebarItem = .list(FeedStore.allFeedsID)
            }
        case .list(let id):
            if id != FeedStore.allFeedsID,
               id != FeedStore.favoritesID,
               !lists.contains(where: { $0.id == id }) {
                selectedSidebarItem = .list(FeedStore.allFeedsID)
            }
        case .category(let name):
            if !feeds.contains(where: { ($0.category ?? "Other") == name }) {
                selectedSidebarItem = .list(FeedStore.allFeedsID)
            }
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites:
            // Media selections are validated by their own stores
            break
        }
    }
}

private struct SeedFeed: Codable {
    let name: String
    let category: String?
    let country: String?
    let site: String
    let feed_url: String
}

private struct FetchedDocument {
    let text: String
    let mimeType: String?
}
