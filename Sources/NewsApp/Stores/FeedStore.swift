import Foundation
import SwiftUI
import AppKit

@MainActor
final class FeedStore: ObservableObject {
    static let allFeedsID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let unreadID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    @Published var feeds: [Feed] = []
    @Published var lists: [UserList] = []
    @Published var articlesByFeed: [UUID: [Article]] = [:] {
        didSet { invalidateArticleCache() }
    }
    @Published var selectedSidebarItem: SidebarSelection? = .list(FeedStore.allFeedsID) {
        didSet {
            guard oldValue != selectedSidebarItem else { return }
            updateUnreadSnapshot(forSelectionChangeFrom: oldValue, to: selectedSidebarItem)
        }
    }
    /// IDs captured the moment the user entered the Unread smart list. Articles in this set
    /// stay visible in the Unread view even after being marked read, so keyboard navigation
    /// doesn't rug-pull. Cleared when the user navigates away.
    @Published private(set) var unreadSnapshotIDs: Set<UUID> = []
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
    /// In-flight debounced article persistence task. Coalesces frequent mutations
    /// (mark-read, refresh, etc.) into a single disk write per ~750ms.
    private var pendingArticlePersistTask: Task<Void, Never>?
    private static let articlePersistDebounceMs: UInt64 = 750
    private var willTerminateObserver: NSObjectProtocol?

    // MARK: - Refresh batching
    //
    // During a multi-feed refresh, each completed fetch used to mutate `articlesByFeed`
    // directly. With 1k feeds that produced hundreds of @Published invalidations per
    // second and made the sidebar chop while scrolling. Now per-feed merges are
    // collected in this buffer and flushed in a single tick every ~200ms, with a final
    // flush after the task group completes.
    private var refreshArticleBuffer: [UUID: [Article]] = [:]
    private var refreshFlushTask: Task<Void, Never>?
    /// 500ms cadence balances perceived progress against sidebar invalidation cost.
    /// Tighter intervals smoothed the count animation but invalidated the sidebar too
    /// often during big refreshes and made scrolling feel jittery.
    private static let refreshFlushIntervalMs: UInt64 = 500

    /// Mirror of the for-await loop's completion counter, updated cheaply (no @Published
    /// invalidation). The periodic flush copies this into `refreshCompletedCount`.
    private var inFlightCompletedCount: Int = 0

    /// Progress for the active refresh. Set once at the start, ticked by the periodic
    /// flusher so views see one batched update per tick instead of one per feed.
    @Published private(set) var refreshTotalCount: Int = 0
    @Published private(set) var refreshCompletedCount: Int = 0

    // Polymarket sort cache: [feedID: [sort: articles]]
    private var polymarketSortCache: [UUID: [PolymarketSort: [Article]]] = [:]
    @Published var polymarketLoadingFeedID: UUID?

    /// O(1) cache of unread counts per feed, kept in sync with `articlesByFeed`.
    /// Sidebar badge math used to iterate every feed's article list on every render —
    /// with 1k feeds that scaled poorly. Now: update incrementally at every mutation.
    @Published private(set) var unreadCountByFeed: [UUID: Int] = [:]

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
        rebuildUnreadCountCache()
        registerTerminationFlush()
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

        // Auto-refresh on launch — conditional GET path. Only feeds older
        // than the 5-minute staleness threshold get hit, and they use stored
        // etag / last-modified headers so most respond 304 with no body.
        //
        // We intentionally do NOT force-refresh here. A `force: true` on a
        // 1k-feed library means every server gets a full body request before
        // the worker pool drains; during those minutes the constant
        // `articlesByFeed` flushes starve the article list / cards view of
        // scroll events and leave TV view's article picker empty. Stuck-etag
        // recovery happens only on user-initiated refresh (R key / toolbar).
        Task(priority: .utility) {
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
        beginRefreshBatching(totalCount: staleFeeds.count)
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
                    await MainActor.run { self.inFlightCompletedCount += 1 }
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

        endRefreshBatching()
        persistFeeds(feeds)
        schedulePersistArticles()
        isRefreshing = false
        refreshTotalCount = 0
        refreshCompletedCount = 0
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

    /// Refresh every fetchable feed.
    ///
    /// - Parameter force: When `true`, clears each feed's stored `etag` /
    ///   `lastModified` before fetching, so the server can't reply 304 Not
    ///   Modified — we always get a full body and re-parse. This is the path
    ///   for user-initiated refresh (R key, toolbar button) because it
    ///   guarantees stale-etag situations recover. Background auto-refresh
    ///   leaves `force` false so it keeps the bandwidth-friendly conditional
    ///   GET.
    func refreshAll(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let timer = logger.begin("refreshAll")
        logger.log("Refresh start feeds=\(feeds.count) force=\(force)")

        if force {
            // Drop the conditional-GET state so every request is unconditional.
            // Without this, a feed that was successfully fetched once but later
            // had its articles wiped by retention cleanup stays empty forever
            // (server keeps replying 304 against the surviving etag).
            for index in feeds.indices {
                feeds[index].etag = nil
                feeds[index].lastModified = nil
            }
        }

        // Get feeds that can be fetched, prioritizing selected feed
        let selectedFeedID: UUID? = {
            if case .feed(let id) = selectedSidebarItem { return id }
            return nil
        }()

        let prioritized = feeds.enumerated().filter { _, feed in
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
        // Round-robin by host so no single host (e.g. Reddit's 800 subreddit feeds)
        // monopolizes the first concurrent slots. Selected feed stays at the front.
        let fetchableFeeds = interleaveByHost(prioritized, pinningFront: selectedFeedID)

        let totalFeeds = fetchableFeeds.count
        var completedFeeds = 0

        // Begin batched UI updates — fetchSingleFeed will write to the buffer instead
        // of `articlesByFeed` directly so that sidebar invalidations stay throttled.
        beginRefreshBatching(totalCount: totalFeeds)

        // Parallel fetch with controlled concurrency. 24 keeps the worker pool full
        // when slow / rate-limited hosts (Reddit, large news sites) stall some slots,
        // while staying well below URLSession's per-host limit (6) so we don't pile
        // extra pressure on any single host.
        await withTaskGroup(of: FeedFetchResult?.self) { group in
            let maxConcurrent = 24
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

            // Process results and start new tasks as others complete. Counter is
            // incremented locally and mirrored to inFlightCompletedCount; the periodic
            // flush task copies it into the @Published `refreshCompletedCount` so views
            // see one update per tick instead of one per feed.
            for await _ in group {
                activeTasks -= 1
                completedFeeds += 1
                inFlightCompletedCount = completedFeeds

                // Start next task if available
                _ = startNextFetch()
            }
        }

        // End batching: cancel the periodic task and apply the final flush so any
        // buffered updates from the last few seconds land before we mark "done".
        endRefreshBatching()

        // Final persist (debounced — coalesces with any in-flight mark-read writes)
        persistFeeds(feeds)
        schedulePersistArticles()

        isRefreshing = false
        statusMessage = nil
        refreshTotalCount = 0
        refreshCompletedCount = 0
        lastRefreshTime = Date()
        extendUnreadSnapshotForRefresh()
        timer.end()
        logger.log("Refresh finished count=\(completedFeeds)")
    }

    // MARK: - Refresh batching helpers

    private func beginRefreshBatching(totalCount: Int) {
        refreshArticleBuffer = [:]
        inFlightCompletedCount = 0
        refreshTotalCount = totalCount
        refreshCompletedCount = 0
        refreshFlushTask?.cancel()
        refreshFlushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: FeedStore.refreshFlushIntervalMs * 1_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.flushRefreshBatch()
            }
        }
    }

    private func endRefreshBatching() {
        refreshFlushTask?.cancel()
        refreshFlushTask = nil
        flushRefreshBatch()
    }

    /// Apply all pending per-feed merges in a single tick. The previous version
    /// subscripted `articlesByFeed[id] = …` and called `refreshUnreadCount(for:)` in a
    /// loop — each of those is a @Published dictionary write that fires
    /// `objectWillChange`, so a 150-feed batch produced 300 sidebar invalidations.
    /// Now we build the new dictionaries locally and assign each one exactly once,
    /// so a flush is two invalidations regardless of batch size.
    private func flushRefreshBatch() {
        if !refreshArticleBuffer.isEmpty {
            var newArticles = articlesByFeed
            var newCounts = unreadCountByFeed
            for (feedID, articles) in refreshArticleBuffer {
                newArticles[feedID] = articles
                newCounts[feedID] = articles.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
            }
            articlesByFeed = newArticles
            unreadCountByFeed = newCounts
            refreshArticleBuffer.removeAll(keepingCapacity: true)
        }
        if refreshCompletedCount != inFlightCompletedCount {
            refreshCompletedCount = inFlightCompletedCount
        }
    }

    /// Helper that returns the merged articles for a feed, peeking at the in-flight
    /// refresh buffer first so consecutive fetches of the same feed don't lose data.
    private func currentArticles(for feedID: UUID) -> [Article] {
        refreshArticleBuffer[feedID] ?? articlesByFeed[feedID] ?? []
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

            // Update state on main actor. During a full refresh, the merged article
            // list goes into `refreshArticleBuffer` and is committed in batched ticks
            // by the periodic flush task — that keeps the sidebar from invalidating
            // on every single per-feed completion.
            await MainActor.run {
                if let idx = feeds.firstIndex(where: { $0.id == feed.id }) {
                    if let entries = result.entries {
                        let existing = currentArticles(for: feed.id)
                        let merged = merge(entries: entries, existing: existing, feed: feeds[idx])
                        refreshArticleBuffer[feed.id] = merged
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
                    refreshUnreadCount(for: feeds[index].id)
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
                refreshUnreadCount(for: feeds[index].id)
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
                refreshUnreadCount(for: feeds[index].id)
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
        schedulePersistArticles()
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
            await refresh(feedID: feed.id)
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
            let existing = articlesByFeed[feedID] ?? []
            let newArticles = merge(entries: entries, existing: existing, feed: feeds[index])

            // Update cache and UI
            if polymarketSortCache[feedID] == nil {
                polymarketSortCache[feedID] = [:]
            }
            polymarketSortCache[feedID]?[sort] = newArticles
            articlesByFeed[feedID] = newArticles
            refreshUnreadCount(for: feedID)
            schedulePersistArticles()
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
        ids.forEach {
            articlesByFeed[$0] = nil
            unreadCountByFeed[$0] = nil
        }
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
        schedulePersistArticles()
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
        unreadCountByFeed[id] = nil
        // Remove from all lists
        for i in lists.indices {
            lists[i].feedIDs.removeAll { $0 == id }
        }
        persistFeeds(feeds)
        persistLists(lists)
        schedulePersistArticles()
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
        let wasRead = list[index].isRead
        guard wasRead != isRead else { return }
        list[index].isRead = isRead
        articlesByFeed[article.feedID] = list
        adjustUnreadCount(for: article.feedID, delta: isRead ? -1 : 1)
        schedulePersistArticles()
        if isRead {
            clearUnreadSnapshotIfAllRead()
        }
    }

    func toggleStar(_ article: Article) {
        guard var list = articlesByFeed[article.feedID],
              let index = list.firstIndex(where: { $0.id == article.id }) else { return }
        list[index].isStarred.toggle()
        articlesByFeed[article.feedID] = list
        schedulePersistArticles()
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

    /// Reorder user-created lists in the sidebar. Wired to `.onMove` on the user
    /// list ForEach so the drag handle and animation come for free.
    func removeList(id: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        removeLists(at: IndexSet(integer: index))
    }

    func moveLists(fromOffsets: IndexSet, toOffset: Int) {
        lists.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persistLists(lists)
        invalidateArticleCache()
    }

    func moveList(id: UUID, to index: Int) {
        guard let sourceIndex = lists.firstIndex(where: { $0.id == id }) else { return }
        let list = lists.remove(at: sourceIndex)
        let targetIndex = min(max(index, 0), lists.count)
        guard sourceIndex != targetIndex else {
            lists.insert(list, at: sourceIndex)
            return
        }
        lists.insert(list, at: targetIndex)
        persistLists(lists)
        invalidateArticleCache()
    }

    func reorderLists(matching orderedIDs: [UUID]) {
        guard !orderedIDs.isEmpty else { return }
        let orderIndex = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        let reordered = lists.enumerated().sorted { lhs, rhs in
            switch (orderIndex[lhs.element.id], orderIndex[rhs.element.id]) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
        guard reordered != lists else { return }
        lists = reordered
        persistLists(lists)
        invalidateArticleCache()
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
        pendingArticlePersistTask?.cancel()
        pendingArticlePersistTask = nil
        refreshArticleBuffer.removeAll()
        sortedArticlesCache.removeAll()
        articleIndex.removeAll()
        isArticleIndexDirty = true
        polymarketSortCache.removeAll()
        unreadSnapshotIDs = []
        selectedArticleID = nil
        articlesByFeed = [:]
        unreadCountByFeed = [:]
        persistenceQueue.sync {
            persistence.resetCache()
        }
        URLCache.shared.removeAllCachedResponses()
        PolymarketService.clearCache()
        logger.log("Cache cleared")
    }

    func cacheStorageUsage() -> CacheStorageUsage {
        let articleBytes = persistenceQueue.sync {
            persistence.articleCacheSizeBytes()
        }
        let sharedCacheBytes = Int64(URLCache.shared.currentDiskUsage)
        let polymarketCacheBytes = Int64(PolymarketService.cacheDiskUsage)
        return CacheStorageUsage(
            articleBytes: articleBytes,
            networkCacheBytes: sharedCacheBytes + polymarketCacheBytes
        )
    }

    /// Mark all articles as read for a specific selection
    func markAllAsRead(for selection: SidebarSelection?) {
        let articlesToMark = articles(for: selection)
        var updatedCount = 0
        var affectedFeeds = Set<UUID>()

        for article in articlesToMark where !article.isRead {
            if var list = articlesByFeed[article.feedID],
               let index = list.firstIndex(where: { $0.id == article.id }) {
                list[index].isRead = true
                articlesByFeed[article.feedID] = list
                affectedFeeds.insert(article.feedID)
                updatedCount += 1
            }
        }

        if updatedCount > 0 {
            for feedID in affectedFeeds {
                refreshUnreadCount(for: feedID)
            }
            schedulePersistArticles()
            invalidateArticleCache()
            logger.log("Marked all read count=\(updatedCount)")
        }
        clearUnreadSnapshotIfAllRead()
    }

    /// Number of most-recent articles to keep per feed regardless of the
    /// retention cutoff. Stops feeds with infrequent publishing from going
    /// completely empty when their items age past the retention window.
    private static let retentionFloorPerFeed = 10

    /// Clean up old articles based on retention period.
    ///
    /// Always preserved:
    /// - Starred (bookmarked) articles.
    /// - The `retentionFloorPerFeed` most-recent articles per feed (so a feed
    ///   that publishes once a quarter still shows its latest post under a
    ///   30-day retention setting).
    func cleanupOldArticles(retentionDays: Int) {
        guard retentionDays > 0 else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        var totalRemoved = 0

        for (feedID, articles) in articlesByFeed {
            // Sort newest → oldest so the "keep latest N" floor is deterministic.
            let sorted = articles.sorted { a, b in
                (a.publishedAt ?? a.addedAt) > (b.publishedAt ?? b.addedAt)
            }
            let floorCutoffIndex = min(Self.retentionFloorPerFeed, sorted.count)

            let filtered = sorted.enumerated().compactMap { (idx, article) -> Article? in
                if article.isStarred { return article }
                // Top-N most recent always survive, even if they're older than
                // the retention cutoff.
                if idx < floorCutoffIndex { return article }
                let articleDate = article.publishedAt ?? article.addedAt
                return articleDate > cutoffDate ? article : nil
            }

            let removed = articles.count - filtered.count
            if removed > 0 {
                articlesByFeed[feedID] = filtered
                refreshUnreadCount(for: feedID)
                totalRemoved += removed
            }
        }

        if totalRemoved > 0 {
            schedulePersistArticles()
            invalidateArticleCache()
            logger.log("Cleanup removed old articles count=\(totalRemoved) cutoff=\(retentionDays) days floor=\(Self.retentionFloorPerFeed)")
        }
    }

    func importOPML(from url: URL) -> Int {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else { return 0 }
        let imported = opmlService.parse(data: data)
        guard !imported.isEmpty else { return 0 }

        // Build the new feed array in a local before assigning back, so SwiftUI sees
        // a single @Published change instead of one per import row. At thousands of
        // feeds this turns a wave of re-renders into one.
        let existing = Set(feeds.map { $0.feedURL.absoluteString })
        var newFeeds: [Feed] = []
        newFeeds.reserveCapacity(imported.count)
        for feed in imported where !existing.contains(feed.xmlURL.absoluteString) {
            newFeeds.append(Feed(name: feed.title, feedURL: feed.xmlURL, siteURL: feed.htmlURL))
        }
        guard !newFeeds.isEmpty else {
            logger.log("OPML import added=0 (all duplicates)")
            return 0
        }
        feeds = feeds + newFeeds
        persistFeeds(feeds)
        invalidateArticleCache()
        logger.log("OPML import added=\(newFeeds.count)")
        return newFeeds.count
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
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites, .radioUserStations:
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

    /// Get the badge count for a feed based on the specified mode. Hot path —
    /// called once per visible sidebar row on every render. `.unread` mode is
    /// served from `unreadCountByFeed` in O(1); the time-windowed modes still
    /// scan the feed's article list (uncommon and small in practice).
    func feedBadgeCount(for feedID: UUID, mode: BadgeCountMode) -> Int {
        if mode == .unread {
            return unreadCountByFeed[feedID] ?? 0
        }
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

    /// Get the badge count for a list based on the specified mode.
    ///
    /// Smart lists have fixed badge semantics so they convey distinct information at a glance:
    ///   - All Feeds  → total article count (library size)
    ///   - Unread     → live unread count (independent of the snapshot used for the view)
    ///   - Bookmarks  → handled by the row directly via `showBookmarkCount`
    ///   - Custom lists → respect the user's `BadgeCountMode`
    func listBadgeCount(for listID: UUID, mode: BadgeCountMode) -> Int {
        if listID == FeedStore.allFeedsID {
            return allArticles().count
        }
        if listID == FeedStore.unreadID {
            return allArticles().filter { !$0.isRead }.count
        }
        return badgeCount(for: .list(listID), mode: mode)
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
        if id == FeedStore.unreadID {
            return "Unread"
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
    /// The exact, top-to-bottom list of selectable sidebar rows — the same order,
    /// filtering, and collapse behavior that `FeedListView` renders. Keyboard
    /// navigation walks this so arrows move row-by-row down what's actually on
    /// screen instead of a separate hardcoded alphabetical order. Feeds inside a
    /// collapsed category/list are intentionally omitted (they aren't visible).
    func orderedSidebarItems(settings: SettingsStore, radioEnabled: Bool, hasRadioFavorites: Bool, hasUserStations: Bool) -> [SidebarSelection] {
        var items: [SidebarSelection] = []

        // Smart lists — always visible, fixed order.
        items.append(.list(FeedStore.allFeedsID))
        items.append(.list(FeedStore.unreadID))
        items.append(.list(FeedStore.favoritesID))

        let filterUnread = settings.sidebarFilterUnreadOnly
        let grouped = Dictionary(grouping: feeds, by: { $0.category ?? "Other" })

        // Mirror FeedListView.visibleUserLists / visibleCategoryNames.
        let visibleLists = lists.filter { list in
            if !filterUnread { return true }
            return listBadgeCount(for: list.id, mode: .unread) > 0
        }
        func categoryUnread(_ category: String) -> Int {
            (grouped[category] ?? []).reduce(0) { $0 + feedBadgeCount(for: $1.id, mode: .unread) }
        }
        let visibleCategories: [String] = grouped.keys.filter { category in
            if !filterUnread { return true }
            return categoryUnread(category) > 0
        }

        // Mirror FeedListView.visibleFeeds(in:) for both flavors.
        func visibleFeeds(inCategory category: String) -> [Feed] {
            var fs = grouped[category] ?? []
            if filterUnread { fs = fs.filter { feedBadgeCount(for: $0.id, mode: .unread) > 0 } }
            switch settings.sidebarSortMode {
            case .byUnreadCount:
                return fs.sorted { a, b in
                    let ac = feedBadgeCount(for: a.id, mode: .unread)
                    let bc = feedBadgeCount(for: b.id, mode: .unread)
                    if ac != bc { return ac > bc }
                    return a.name < b.name
                }
            case .alphabetical, .custom:
                return fs.sorted { $0.name < $1.name }
            }
        }
        func visibleFeeds(inList list: UserList) -> [Feed] {
            let byID = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
            var fs = list.feedIDs.compactMap { byID[$0] }
            if filterUnread { fs = fs.filter { feedBadgeCount(for: $0.id, mode: .unread) > 0 } }
            switch settings.sidebarSortMode {
            case .byUnreadCount:
                return fs.sorted { a, b in
                    let ac = feedBadgeCount(for: a.id, mode: .unread)
                    let bc = feedBadgeCount(for: b.id, mode: .unread)
                    if ac != bc { return ac > bc }
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            case .alphabetical, .custom:
                return fs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }

        // A list/category header is selectable; its children follow only when expanded.
        func appendList(_ list: UserList) {
            items.append(.list(list.id))
            if !settings.collapsedListIDs.contains(list.id) {
                for feed in visibleFeeds(inList: list) { items.append(.feed(feed.id)) }
            }
        }
        func appendCategory(_ category: String) {
            items.append(.category(category))
            if !settings.collapsedCategories.contains(category) {
                for feed in visibleFeeds(inCategory: category) { items.append(.feed(feed.id)) }
            }
        }

        switch settings.sidebarSortMode {
        case .custom:
            let defaultItems = visibleLists.map { SidebarCustomOrderItem.list($0.id) }
                + CategorySorting.applyCustom(order: settings.customCategoryOrder, to: visibleCategories)
                    .map { SidebarCustomOrderItem.category($0) }
            let ordered = CategorySorting.applyCustomSidebarOrder(
                order: settings.customSidebarItemOrder,
                to: defaultItems
            )
            for item in ordered {
                switch item.kind {
                case .list:
                    if let id = UUID(uuidString: item.value),
                       let list = visibleLists.first(where: { $0.id == id }) {
                        appendList(list)
                    }
                case .category:
                    if visibleCategories.contains(item.value) {
                        appendCategory(item.value)
                    }
                }
            }
        case .alphabetical:
            for list in visibleLists { appendList(list) }
            for category in visibleCategories.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                appendCategory(category)
            }
        case .byUnreadCount:
            for list in visibleLists { appendList(list) }
            let sortedCats = visibleCategories.sorted { c1, c2 in
                let a = categoryUnread(c1)
                let b = categoryUnread(c2)
                if a != b { return a > b }
                return c1 < c2
            }
            for category in sortedCats { appendCategory(category) }
        }

        // Radio section — mirrors the rows FeedListView shows when each is non-empty.
        if radioEnabled {
            items.append(.radioBrowse)
            if hasRadioFavorites { items.append(.radioFavorites) }
            if hasUserStations { items.append(.radioUserStations) }
        }

        return items
    }

    /// Navigate to prev/next sidebar item, stepping through the exact visible rows.
    func navigateSidebar(direction: Int, settings: SettingsStore, radioEnabled: Bool, hasRadioFavorites: Bool, hasUserStations: Bool) {
        let items = orderedSidebarItems(
            settings: settings,
            radioEnabled: radioEnabled,
            hasRadioFavorites: hasRadioFavorites,
            hasUserStations: hasUserStations
        )
        guard !items.isEmpty else { return }
        // If the current selection isn't in the visible list (e.g. a feed whose
        // category was just collapsed), fall back to a sensible anchor so the next
        // press still moves predictably: top when going down, bottom when going up.
        let currentIndex = items.firstIndex(of: selectedSidebarItem ?? .list(FeedStore.allFeedsID))
            ?? (direction > 0 ? -1 : items.count)
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
                schedulePersistArticles()
                return
            }
        }
    }

    /// Discover og:image for articles that are missing images.
    /// Fetches article pages concurrently (up to 6 at a time) and updates the model.
    /// Returns the number of articles whose imageURL was newly populated, so callers
    /// can decide whether a re-render (e.g. a snapshot rebuild) is worthwhile.
    @discardableResult
    func discoverImages(for articles: [Article], limit: Int = 30) async -> Int {
        let missing = articles.filter { $0.imageURL == nil && $0.link != nil && !isLikelyMediaURL($0.link!) }
        guard !missing.isEmpty else { return 0 }

        var updated = 0
        await withTaskGroup(of: (UUID, URL?).self) { group in
            var launched = 0
            for article in missing.prefix(limit) {
                guard let link = article.link else { continue }
                launched += 1
                if launched > 6 {
                    // Wait for one to finish before launching more
                    if let result = await group.next(), let url = result.1 {
                        await MainActor.run { updateArticle(articleID: result.0, contentText: nil, imageURL: url) }
                        updated += 1
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
                    updated += 1
                }
            }
        }
        return updated
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
                let parsedTitle = entry.title.decodingHTMLEntities()
                if !parsedTitle.isEmpty, parsedTitle != "Untitled", existing.title != parsedTitle {
                    existing.title = parsedTitle
                }
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
            if starred.count >= 500 {
                list = starred
            } else {
                let unstarredLimit = 500 - starred.count
                let unstarred = list.filter { !$0.isStarred }.prefix(unstarredLimit)
                list = starred + unstarred
            }
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

    /// Reorder a prioritized feed list so consecutive entries come from different
    /// hosts whenever possible. With ~800 Reddit feeds in a 1k-feed corpus, the
    /// natural order would have them clumped together and burn through Reddit's
    /// rate limit immediately while non-Reddit hosts wait. Round-robin guarantees
    /// each host gets a turn before any host is sampled twice.
    private func interleaveByHost(
        _ feeds: [(offset: Int, element: Feed)],
        pinningFront pinnedID: UUID?
    ) -> [(offset: Int, element: Feed)] {
        var pinned: (offset: Int, element: Feed)?
        var byHost: [String: [(offset: Int, element: Feed)]] = [:]
        var hostOrder: [String] = []  // preserves the input priority of each host
        for entry in feeds {
            if entry.element.id == pinnedID {
                pinned = entry
                continue
            }
            let host = entry.element.feedURL.host?.lowercased() ?? ""
            if byHost[host] == nil {
                hostOrder.append(host)
            }
            byHost[host, default: []].append(entry)
        }

        var interleaved: [(offset: Int, element: Feed)] = []
        if let pinned { interleaved.append(pinned) }
        var rounds = 0
        let maxRoundsPossible = byHost.values.map(\.count).max() ?? 0
        while rounds < maxRoundsPossible {
            for host in hostOrder {
                if var bucket = byHost[host], rounds < bucket.count {
                    interleaved.append(bucket[rounds])
                    byHost[host] = bucket
                }
            }
            rounds += 1
        }
        return interleaved
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
        if id == FeedStore.unreadID {
            return allArticles().filter { unreadSnapshotIDs.contains($0.id) }
        }
        guard let list = lists.first(where: { $0.id == id }) else { return [] }
        let selected = Set(list.feedIDs)
        guard !selected.isEmpty else { return [] }
        return articlesByFeed
            .filter { selected.contains($0.key) }
            .flatMap { $0.value }
    }

    // MARK: - Unread snapshot lifecycle

    /// Capture the set of currently-unread article IDs. Used when entering the Unread smart list
    /// so subsequent `isRead = true` mutations don't immediately remove rows from the visible list.
    private func captureUnreadSnapshot() {
        unreadSnapshotIDs = Set(allArticles().compactMap { $0.isRead ? nil : $0.id })
    }

    private func updateUnreadSnapshot(forSelectionChangeFrom previous: SidebarSelection?, to next: SidebarSelection?) {
        let wasUnread = previous == .list(FeedStore.unreadID)
        let isUnread = next == .list(FeedStore.unreadID)
        if !wasUnread && isUnread {
            // Re-entering Unread: rebuild the snapshot from what's *currently* unread so
            // stories read on the last visit drop out immediately. Invalidate the article
            // cache too — otherwise the middle column keeps showing the stale cached list
            // (the read story lingered until some other action cleared the cache).
            captureUnreadSnapshot()
            invalidateArticleCache()
        } else if wasUnread && !isUnread {
            unreadSnapshotIDs = []
        }
    }

    /// If currently in the Unread view, fold any newly-unread articles into the snapshot so
    /// refresh results appear inline without rebuilding the existing entries.
    private func extendUnreadSnapshotForRefresh() {
        guard selectedSidebarItem == .list(FeedStore.unreadID) else { return }
        for article in allArticles() where !article.isRead {
            unreadSnapshotIDs.insert(article.id)
        }
    }

    /// If we're in the Unread view and every article in the snapshot has been read, clear
    /// the snapshot so the article list collapses to the "All caught up" empty state
    /// instead of a ghost list of already-read items.
    private func clearUnreadSnapshotIfAllRead() {
        guard selectedSidebarItem == .list(FeedStore.unreadID) else { return }
        guard !unreadSnapshotIDs.isEmpty else { return }
        let snapshotIDs = unreadSnapshotIDs
        for articles in articlesByFeed.values {
            for article in articles where snapshotIDs.contains(article.id) && !article.isRead {
                return
            }
        }
        unreadSnapshotIDs = []
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

    // MARK: - Debounced article persistence

    /// Schedule a coalesced article write. Multiple calls within
    /// `articlePersistDebounceMs` collapse into a single full-corpus encode + write.
    /// Used instead of the previous fire-every-mutation `persistArticles(allArticles())`
    /// pattern; in a refresh of 1k feeds the old pattern wrote ~1k times.
    func schedulePersistArticles() {
        pendingArticlePersistTask?.cancel()
        pendingArticlePersistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: FeedStore.articlePersistDebounceMs * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.persistArticlesNow()
        }
    }

    /// Observe `NSApplication.willTerminateNotification` so an in-flight debounce
    /// always flushes before the process exits. The notification is delivered on the
    /// main queue (we request it explicitly) so we can call the @MainActor flush
    /// synchronously via `MainActor.assumeIsolated`.
    private func registerTerminationFlush() {
        guard willTerminateObserver == nil else { return }
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushPendingPersistence()
            }
        }
    }

    /// Cancel any pending debounce and synchronously flush. Wired to
    /// `applicationWillTerminate` so an in-flight debounce doesn't lose mark-reads
    /// or freshly-fetched articles on quit.
    func flushPendingPersistence() {
        pendingArticlePersistTask?.cancel()
        pendingArticlePersistTask = nil
        let articles = allArticles()
        persistenceQueue.sync {
            persistence.saveArticles(articles)
        }
    }

    private func persistArticlesNow() {
        let articles = allArticles()
        persistenceQueue.async { [persistence] in
            persistence.saveArticles(articles)
        }
    }

    // MARK: - Unread count cache

    /// Rebuild the per-feed unread count cache from scratch. O(total articles); only
    /// called at app launch.
    private func rebuildUnreadCountCache() {
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(articlesByFeed.count)
        for (feedID, articles) in articlesByFeed {
            counts[feedID] = articles.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
        }
        unreadCountByFeed = counts
    }

    /// Recompute and store the unread count for one feed. Call after replacing the
    /// feed's article list (refresh, merge, cleanup).
    private func refreshUnreadCount(for feedID: UUID) {
        unreadCountByFeed[feedID] = (articlesByFeed[feedID] ?? []).reduce(0) {
            $0 + ($1.isRead ? 0 : 1)
        }
    }

    /// Adjust the cached count by ±1 for individual mark-read toggles.
    private func adjustUnreadCount(for feedID: UUID, delta: Int) {
        let current = unreadCountByFeed[feedID] ?? 0
        unreadCountByFeed[feedID] = max(0, current + delta)
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
               id != FeedStore.unreadID,
               !lists.contains(where: { $0.id == id }) {
                selectedSidebarItem = .list(FeedStore.allFeedsID)
            }
        case .category(let name):
            if !feeds.contains(where: { ($0.category ?? "Other") == name }) {
                selectedSidebarItem = .list(FeedStore.allFeedsID)
            }
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites, .radioUserStations:
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
