import SwiftUI

struct MasonryCardsView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Binding var isPresented: Bool
    @State private var selectedArticle: Article?
    @State private var showReader = false
    @State private var isReaderExpanded = false
    /// Cached, deduplicated, grouped view data. Recomputed on a debounce (~1s) when
    /// the underlying article corpus changes during a refresh — without this snapshot,
    /// every per-flush invalidation would re-run the dedup + grouping passes on the
    /// main thread and beach-ball the cards view.
    @State private var snapshot: MasonrySnapshot = .empty
    @State private var snapshotTask: Task<Void, Never>?
    @State private var discoverTask: Task<Void, Never>?
    private let imagePrefetcher = ImagePrefetcher.shared

    /// Upper bound on cards rendered per category section. The newspaper shows as
    /// many stories as a category has, capped here so an enormous category (or the
    /// all-feeds firehose) can't lay out thousands of cards in one section.
    private static let maxStoriesPerCategory = 30

    var body: some View {
        Group {
            if isReaderExpanded {
                ExpandedReaderView(isExpanded: $isReaderExpanded, showReaderPane: $showReader)
                    .frame(minWidth: 800, minHeight: 600)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ZStack {
                    cardsContent
                    if showReader, selectedArticle != nil {
                        readerOverlay
                    }
                }
            }
        }
        // ESC routing for closing Newspaper view goes through the main
        // keyboard monitor instead of `.focusable() + .onKeyPress`. The
        // SwiftUI focusable modifier inserts an NSResponder above the
        // ScrollView that on macOS 26 swallows mouse-wheel events — the
        // symptom is "scrollbar drag works, keyboard works, wheel doesn't."
        .onChange(of: showReader) { _, new in
            if !new {
                selectedArticle = nil
                feedStore.selectedArticleID = nil
            }
        }
        .task {
            rebuildSnapshot(immediate: true)
            prefetchImages()
            discoverImagesForSelection()
        }
        .onChange(of: feedStore.selectedSidebarItem) { _, _ in
            rebuildSnapshot(immediate: true)
            prefetchImages()
            discoverImagesForSelection()
        }
        // No `onChange(of: refreshCompletedCount)`. Snapshot rebuilds during a
        // refresh are intentionally skipped (the dictionary swap was what
        // reset accumulated scroll-wheel deltas), and observing this @Published
        // value here just invalidates the view body every refresh tick for
        // nothing. The final update arrives via `lastRefreshTime` below.
        .onChange(of: feedStore.lastRefreshTime) { _, _ in
            rebuildSnapshot(immediate: true)
            discoverImagesForSelection()
        }
        .onChange(of: settings.sidebarSortMode) { _, _ in
            rebuildSnapshot(immediate: true)
        }
        .onChange(of: settings.customCategoryOrderJSON) { _, _ in
            rebuildSnapshot(immediate: true)
        }
    }

    // MARK: - Cards Content

    private var cardsContent: some View {
        GeometryReader { geo in
            let columns = columnCount(for: geo.size.width)
            let padding: CGFloat = geo.size.width > 1200 ? 48 : (geo.size.width > 800 ? 32 : 20)

            ScrollView {
                // LazyVStack defers category-section construction until each section
                // scrolls into view. With thousands of articles this is the difference
                // between a long beach ball on first appear and a snappy initial paint.
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Newspaper Masthead
                    mastheadView
                        .padding(.horizontal, padding)
                        .padding(.top, 20)

                    // Lead story section — reads from the cached snapshot so the heavy
                    // dedup + grouping work doesn't re-run on every view body pass.
                    let allArticles = snapshot.allArticles
                    if !allArticles.isEmpty {
                        leadStorySection(
                            articles: allArticles,
                            width: geo.size.width,
                            padding: padding
                        )
                        .padding(.horizontal, padding)
                        .padding(.top, 20)
                    }

                    // Category sections
                    let groupedArticles = snapshot.groupedByCategory

                    if groupedArticles.isEmpty && allArticles.isEmpty {
                        emptyState
                            .padding(.horizontal, padding)
                    } else {
                        ForEach(groupedArticles, id: \.category) { group in
                            categorySection(
                                category: group.category,
                                articles: group.articles,
                                columns: columns,
                                padding: padding
                            )
                        }
                    }

                    // Footer
                    newspaperFooter
                        .padding(.horizontal, padding)
                        .padding(.top, 32)
                        .padding(.bottom, 48)
                }
            }
        }
    }

    // MARK: - Newspaper Masthead

    private var mastheadView: some View {
        VStack(spacing: 0) {
            // Top double rule
            Rectangle().fill(.primary).frame(height: 3)
            Spacer().frame(height: 2)
            Rectangle().fill(.primary.opacity(0.5)).frame(height: 1)

            Spacer().frame(height: 14)

            // Masthead title
            Text(mastheadTitle.uppercased())
                .font(.system(size: settings.scaled(34), weight: .black, design: .serif))
                .tracking(6)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 6)

            // Edition line
            HStack(spacing: 0) {
                ruleExpander
                Text("  \(formattedDate)  •  \(editionLabel)  ")
                    .font(.system(size: settings.scaled(11), weight: .regular))
                    .foregroundStyle(.secondary)
                ruleExpander
            }

            Spacer().frame(height: 6)

            // Subtitle with article count
            Text("\(articleCount) stories from your feeds")
                .font(.system(size: settings.scaled(11)))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 14)

            // Bottom rule
            Rectangle().fill(.primary.opacity(0.5)).frame(height: 1)
            Spacer().frame(height: 2)
            Rectangle().fill(.primary).frame(height: 3)
        }
    }

    private var ruleExpander: some View {
        VStack {
            Spacer()
            Rectangle().fill(.primary.opacity(0.2)).frame(height: 1)
            Spacer()
        }
        .frame(height: 14)
    }

    private var mastheadTitle: String {
        switch feedStore.selectedSidebarItem {
        case .list(let id):
            if id == FeedStore.allFeedsID { return "The Daily Digest" }
            if id == FeedStore.favoritesID { return "Bookmarks" }
            return feedStore.lists.first { $0.id == id }?.name ?? "The Daily Digest"
        case .feed(let id):
            return feedStore.feedName(for: id) ?? "Feed"
        case .category(let name):
            return name
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites, .radioUserStations:
            return "Radio"
        case .none:
            return "The Daily Digest"
        }
    }

    private var editionLabel: String {
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let year = cal.component(.year, from: Date())
        return "Vol. \(year - 2024 + 1), No. \(dayOfYear)"
    }

    // MARK: - Lead Story Section

    private func leadStorySection(articles: [Article], width: CGFloat, padding: CGFloat) -> some View {
        let lead = articles[0]
        let secondaries = Array(articles.dropFirst().prefix(3))
        let useWideLayout = width > 900

        return VStack(spacing: 0) {
            if useWideLayout {
                // Wide layout: lead on left, secondaries on right
                HStack(alignment: .top, spacing: 0) {
                    // Lead story
                    leadArticleView(lead)
                        .frame(maxWidth: .infinity)

                    // Vertical rule
                    Rectangle()
                        .fill(.primary.opacity(0.15))
                        .frame(width: 1)
                        .padding(.vertical, 8)

                    // Secondary stories stack
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(secondaries.enumerated()), id: \.element.id) { index, article in
                            secondaryArticleView(article)
                            if index < secondaries.count - 1 {
                                Rectangle()
                                    .fill(.primary.opacity(0.1))
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .frame(width: min(width * 0.32, 380))
                }
            } else {
                // Narrow layout: lead stacked above secondaries
                leadArticleView(lead)

                Rectangle()
                    .fill(.primary.opacity(0.1))
                    .frame(height: 1)
                    .padding(.top, 16)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(secondaries.enumerated()), id: \.element.id) { index, article in
                        compactSecondaryView(article)
                            .frame(maxWidth: .infinity)
                        if index < secondaries.count - 1 {
                            Rectangle()
                                .fill(.primary.opacity(0.15))
                                .frame(width: 1)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.top, 12)
            }

            // Section closer
            Spacer().frame(height: 20)
            Rectangle().fill(.primary.opacity(0.3)).frame(height: 2)
        }
    }

    private func leadArticleView(_ article: Article) -> some View {
        Button { selectArticle(article) } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Lead image — fits within a height cap so the photo scales with
                // window width without ever cropping top/bottom. At ~1600pt width
                // a 3:2 photo lands at ~533pt tall; the cap stops a tall image
                // from dominating the masthead.
                if let url = article.imageURL {
                    LeadImageView(url: url)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Source
                if let source = feedStore.feedName(for: article.feedID) {
                    Text(source.uppercased())
                        .font(.system(size: settings.scaled(10), weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                }

                // Headline
                Text(article.title)
                    .font(.system(size: settings.scaled(28), weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)

                // Summary
                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: settings.scaled(14), design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                // Byline
                HStack(spacing: 6) {
                    if let author = article.author, !author.isEmpty {
                        Text("By \(author)")
                            .fontWeight(.medium)
                    }
                    if let time = relativeTime(for: article) {
                        if article.author != nil { Text("•") }
                        Text(time)
                    }
                }
                .font(.system(size: settings.scaled(11)))
                .foregroundStyle(.tertiary)
            }
            .padding(.trailing, 20)
        }
        .buttonStyle(.plain)
    }

    private func secondaryArticleView(_ article: Article) -> some View {
        Button { selectArticle(article) } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let source = feedStore.feedName(for: article.feedID) {
                    Text(source.uppercased())
                        .font(.system(size: settings.scaled(9), weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                }

                Text(article.title)
                    .font(.system(size: settings.scaled(15), weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: settings.scaled(12)))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let time = relativeTime(for: article) {
                    Text(time)
                        .font(.system(size: settings.scaled(10)))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .buttonStyle(.plain)
    }

    private func compactSecondaryView(_ article: Article) -> some View {
        Button { selectArticle(article) } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let source = feedStore.feedName(for: article.feedID) {
                    Text(source.uppercased())
                        .font(.system(size: settings.scaled(9), weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                }
                Text(article.title)
                    .font(.system(size: settings.scaled(14), weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let time = relativeTime(for: article) {
                    Text(time)
                        .font(.system(size: settings.scaled(10)))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Section

    private func categorySection(category: String, articles: [Article], columns: Int, padding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section divider
            HStack(spacing: 10) {
                Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
                Text(category.uppercased())
                    .font(.system(size: settings.scaled(12), weight: .heavy))
                    .foregroundStyle(.secondary)
                    .tracking(2)
                    .layoutPriority(1)
                Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
            }
            .padding(.horizontal, padding)
            .padding(.top, 24)

            // Masonry grid of newspaper cards
            MasonryGrid(columns: columns, spacing: 20) {
                ForEach(articles.prefix(Self.maxStoriesPerCategory)) { article in
                    NewspaperCard(
                        article: article,
                        source: feedStore.feedName(for: article.feedID),
                        onTap: { selectArticle(article) }
                    )
                }
            }
            .padding(.horizontal, padding)
        }
    }

    // MARK: - Footer

    private var newspaperFooter: some View {
        VStack(spacing: 8) {
            Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
            Spacer().frame(height: 4)
            Text("— END OF EDITION —")
                .font(.system(size: settings.scaled(10), weight: .medium))
                .foregroundStyle(.quaternary)
                .tracking(3)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 4)
            Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No stories yet")
                .font(.system(size: settings.scaled(18), weight: .medium, design: .serif))
            Text("Select a feed or refresh to load stories")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Reader Overlay

    private var readerOverlay: some View {
        GeometryReader { geo in
            let modalWidth = min(max(geo.size.width * 0.75, 700), 1200)
            let modalHeight = min(max(geo.size.height * 0.85, 500), geo.size.height - 60)

            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { showReader = false }

                VStack(spacing: 0) {
                    ReaderView(
                        onExpand: { isReaderExpanded = true },
                        onClose: { showReader = false }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: modalWidth, height: modalHeight)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.4), radius: 40, y: 12)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeOut(duration: 0.2), value: showReader)
    }

    // MARK: - Helpers

    private var articleCount: Int { snapshot.allArticles.count }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: Date())
    }

    // MARK: - Snapshot rebuild

    private func rebuildSnapshot(immediate: Bool) {
        // Skip non-immediate rebuilds while a refresh is in flight. Each rebuild
        // swaps the snapshot dictionary, which redraws the LazyVStack and resets
        // the underlying NSScrollView's accumulated wheel-scroll deltas — the
        // visible symptom is "my scroll wheel does nothing while a refresh is
        // running". The final immediate rebuild fires from `lastRefreshTime`'s
        // `.onChange` once refresh completes.
        //
        // Important: this return must come BEFORE cancelling the in-flight task —
        // otherwise selecting a category mid-refresh would queue an `immediate`
        // rebuild, then a refresh tick's `immediate: false` call would cancel
        // that work AND return early, leaving the snapshot empty.
        if !immediate, feedStore.isRefreshing {
            return
        }
        snapshotTask?.cancel()
        snapshotTask = Task { [weak feedStore] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled, let feedStore else { return }

            // Pull the raw inputs on the main actor (FeedStore is @MainActor).
            let raw: [Article]
            let feedInfo: [UUID: (name: String, category: String?)]
            let sortMode: SidebarSortMode
            let customOrder: [String]
            (raw, feedInfo, sortMode, customOrder) = await MainActor.run {
                let selection = feedStore.selectedSidebarItem
                let articles = feedStore.sortedArticles(for: selection)
                let info = Dictionary(uniqueKeysWithValues: feedStore.feeds.map {
                    ($0.id, (name: $0.name, category: $0.category))
                })
                return (articles, info, settings.sidebarSortMode, settings.customCategoryOrder)
            }
            guard !Task.isCancelled else { return }

            // Heavy work off-main: dedup by link/externalID, group by category,
            // sort + cap. With 50k+ articles this is where the beach ball lived.
            var seen = Set<String>()
            seen.reserveCapacity(raw.count)
            var deduped: [Article] = []
            deduped.reserveCapacity(raw.count)
            for article in raw {
                let key = article.link?.absoluteString ?? article.externalID
                if seen.insert(key).inserted {
                    deduped.append(article)
                }
            }
            let remaining = deduped.dropFirst(4)
            var groupedDict: [String: [Article]] = [:]
            for article in remaining {
                let info = feedInfo[article.feedID]
                let category = info?.category ?? info?.name ?? "Other"
                groupedDict[category, default: []].append(article)
            }
            // Decide the section order. Custom uses the user's saved drag-drop
            // arrangement; otherwise keep the long-standing biggest-section-first
            // heuristic that defines the newspaper look.
            let categoryNames = Array(groupedDict.keys)
            let orderedCategories: [String]
            switch sortMode {
            case .custom:
                orderedCategories = CategorySorting.applyCustom(order: customOrder, to: categoryNames)
            default:
                orderedCategories = categoryNames.sorted {
                    (groupedDict[$0]?.count ?? 0) > (groupedDict[$1]?.count ?? 0)
                }
            }
            let grouped = orderedCategories.map { name in
                (category: name, articles: Array((groupedDict[name] ?? []).prefix(Self.maxStoriesPerCategory)))
            }

            guard !Task.isCancelled else { return }
            let newSnapshot = MasonrySnapshot(
                allArticles: deduped,
                groupedByCategory: grouped
            )
            await MainActor.run {
                snapshot = newSnapshot
            }
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        if width > 1600 { return 4 }
        if width > 1200 { return 3 }
        if width > 800 { return 2 }
        return 1
    }

    private func selectArticle(_ article: Article) {
        selectedArticle = article
        feedStore.selectedArticleID = article.id
        withAnimation(.easeOut(duration: 0.2)) {
            showReader = true
        }
    }

    private func prefetchImages() {
        let articles = feedStore.sortedArticles(for: feedStore.selectedSidebarItem)
        let urls = articles.prefix(50).compactMap { $0.imageURL }
        imagePrefetcher.prefetch(urls: urls)
    }

    /// Fill in missing images (og:image) for the *currently selected* articles, then
    /// rebuild the snapshot so the lead story and cards actually render the images
    /// that were just discovered.
    ///
    /// This reads from `sortedArticles(for:)` directly rather than `snapshot.allArticles`,
    /// because `rebuildSnapshot` runs asynchronously — at the moment `.task`/`.onChange`
    /// fire, the snapshot is still the previous (or empty) value. Passing the stale
    /// snapshot here is why filtered category views often showed no hero image: the top
    /// story's image only exists as an og:image, and discovery was never actually run on it.
    private func discoverImagesForSelection() {
        discoverTask?.cancel()
        discoverTask = Task { [weak feedStore] in
            guard let feedStore else { return }
            let articles = feedStore.sortedArticles(for: feedStore.selectedSidebarItem)
            let updated = await feedStore.discoverImages(for: articles)
            guard !Task.isCancelled, updated > 0 else { return }
            rebuildSnapshot(immediate: true)
        }
    }

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTime(for article: Article) -> String? {
        guard let date = article.publishedAt else { return nil }
        return Self.timeFormatter.localizedString(for: date, relativeTo: Date())
    }

}

/// View-side snapshot of the cards layout. Both arrays are pre-deduplicated and
/// pre-grouped; the view body just iterates them. Computed off the main thread by
/// `rebuildSnapshot(immediate:)`.
private struct MasonrySnapshot {
    let allArticles: [Article]
    let groupedByCategory: [(category: String, articles: [Article])]

    static let empty = MasonrySnapshot(allArticles: [], groupedByCategory: [])
}

// MARK: - Lead Image View

private struct LeadImageView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                // Fit (not fill) so we never crop. The host's `.frame(maxHeight:)`
                // caps the upper bound at very wide widths.
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.06))
                    ProgressView().controlSize(.small)
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .task(id: url) {
            if let cached = ImagePrefetcher.shared.image(for: url) { image = cached; return }
            if let loaded = await ImagePrefetcher.shared.loadImage(for: url) { image = loaded }
        }
    }
}

private struct SmallImageView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.06))
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: url) {
            if let cached = ImagePrefetcher.shared.image(for: url) { image = cached; return }
            if let loaded = await ImagePrefetcher.shared.loadImage(for: url) { image = loaded }
        }
    }
}

// MARK: - Newspaper Card

struct NewspaperCard: View {
    @EnvironmentObject private var settings: SettingsStore
    let article: Article
    let source: String?
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var image: NSImage?

    private var isPolymarket: Bool {
        article.isPolymarketArticle
    }

    var body: some View {
        Button(action: onTap) {
            if isPolymarket {
                polymarketContent
            } else {
                newspaperContent
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .task(id: article.imageURL) { await loadImageIfNeeded() }
    }

    // MARK: - Newspaper Article Card

    private var newspaperContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image (sharp corners, no rounding). A small inset around the
            // frame keeps the card's dark chrome visible at the edges even
            // when the image itself has a white/light background (e.g.,
            // press-release logos), so the card boundary stays readable in
            // dark mode.
            if let url = article.imageURL {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.06))
                    if let img = image {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if !ImagePrefetcher.shared.hasFailed(url) {
                        ProgressView().controlSize(.small)
                    }
                }
                // `maxWidth: .infinity` makes the ZStack honor the masonry
                // column's proposed width instead of reporting the image's
                // intrinsic size (wide logos at 180pt tall were ~430pt wide,
                // bleeding past the card boundary). The follow-up `.clipped`
                // then clips the image to the actual column width.
                .frame(maxWidth: .infinity, maxHeight: 180)
                .clipped()
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            // Text content
            VStack(alignment: .leading, spacing: 6) {
                // Source and time
                HStack {
                    if let source = source {
                        Text(source.uppercased())
                            .font(.system(size: settings.scaled(9), weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let time = timeAgo {
                        Text(time)
                            .font(.system(size: settings.scaled(9)))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Headline in serif
                Text(article.title)
                    .font(.system(size: settings.scaled(15), weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(article.imageURL != nil ? 3 : 5)
                    .multilineTextAlignment(.leading)

                // Summary
                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: settings.scaled(12)))
                        .foregroundStyle(.secondary)
                        .lineLimit(article.imageURL != nil ? 2 : 3)
                        .multilineTextAlignment(.leading)
                }

                // Byline
                if let author = article.author, !author.isEmpty {
                    Text("By \(author)")
                        .font(.system(size: settings.scaled(10), weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Bottom rule
            Rectangle()
                .fill(.primary.opacity(0.1))
                .frame(height: 1)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(
            Rectangle()
                .stroke(.primary.opacity(isHovered ? 0.22 : 0.14), lineWidth: 1)
        )
        .opacity(isHovered ? 0.85 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    // MARK: - Polymarket Card (Newspaper Style)

    private var polymarketContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipped()
                } else if let data = article.polymarketData {
                    ZStack {
                        Rectangle()
                            .fill(polymarketColor(data.probability).opacity(0.12))
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 18))
                            .foregroundStyle(polymarketColor(data.probability))
                    }
                    .frame(width: 52, height: 52)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.system(size: settings.scaled(13), weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let data = article.polymarketData, data.isMultiOutcome, let label = data.leadingLabel, !label.isEmpty {
                        Text(label)
                            .font(.system(size: settings.scaled(10)))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)

            if let data = article.polymarketData {
                HStack(spacing: 0) {
                    Text("\(data.probabilityPercent)%")
                        .font(.system(size: settings.scaled(14), weight: .bold, design: .rounded))
                        .foregroundStyle(polymarketColor(data.probability))
                        .frame(minWidth: 40)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.primary.opacity(0.06))
                            Rectangle()
                                .fill(polymarketColor(data.probability))
                                .frame(width: geo.size.width * data.probability)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 8)

                    Spacer()

                    HStack(spacing: 8) {
                        Label(data.formattedVolume24hr, systemImage: "chart.bar.fill")
                        if let timeLeft = data.timeRemaining {
                            Label(timeLeft, systemImage: "clock")
                                .foregroundColor(
                                    (timeLeft.contains("h left") || timeLeft.contains("m left"))
                                    ? .orange : .secondary
                                )
                        }
                    }
                    .font(.system(size: settings.scaled(9), weight: .medium))
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            Rectangle()
                .fill(.primary.opacity(0.1))
                .frame(height: 1)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(
            Rectangle()
                .stroke(.primary.opacity(isHovered ? 0.12 : 0.06), lineWidth: 1)
        )
        .opacity(isHovered ? 0.85 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func polymarketColor(_ probability: Double) -> Color {
        let pct = probability * 100
        if pct >= 80 { return .green }
        if pct >= 50 { return Color(red: 0.3, green: 0.7, blue: 0.4) }
        if pct >= 20 { return .orange }
        return .red
    }

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var timeAgo: String? {
        guard let date = article.publishedAt else { return nil }
        return Self.timeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadImageIfNeeded() async {
        guard let url = article.imageURL, image == nil else { return }
        if let cached = ImagePrefetcher.shared.image(for: url) {
            image = cached; return
        }
        if ImagePrefetcher.shared.hasFailed(url) { return }
        if let loaded = await ImagePrefetcher.shared.loadImage(for: url) {
            image = loaded
        }
    }
}

// MARK: - Weather Widget for Cards View

private struct CardsWeatherWidget: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var weather = SharedWeatherService.shared
    @State private var showingPopover = false

    var body: some View {
        Group {
            if settings.weatherEnabled && hasLocation {
                Button {
                    showingPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        if let data = weather.current {
                            Image(systemName: data.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(data.iconColor)
                            Text("\(data.temperature)°")
                                .font(.system(size: 12, weight: .medium))
                            Text(data.city)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else if weather.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help(weather.current.map { data in
                    let sym = data.units.temperatureSymbol
                    return "\(data.description) in \(data.city)\n\(data.temperature)\(sym) • Feels like \(data.feelsLike)\(sym)"
                } ?? "Weather")
                .popover(isPresented: $showingPopover) {
                    CardsWeatherPopover(data: weather.current, city: displayCity)
                }
                .task {
                    weather.configure(
                        city: displayCity,
                        lat: settings.weatherLatitude,
                        lon: settings.weatherLongitude,
                        units: settings.weatherUnits
                    )
                    weather.fetchIfNeeded()
                }
                .onChange(of: settings.weatherUnits) { _, _ in
                    weather.configure(
                        city: displayCity,
                        lat: settings.weatherLatitude,
                        lon: settings.weatherLongitude,
                        units: settings.weatherUnits
                    )
                    weather.forceRefresh()
                }
            }
        }
    }

    private var hasLocation: Bool {
        settings.weatherLatitude != 0 && settings.weatherLongitude != 0
    }

    private var displayCity: String {
        let full = settings.weatherCity
        if let comma = full.firstIndex(of: ",") {
            return String(full[..<comma])
        }
        return full.isEmpty ? "" : full
    }
}

private struct CardsWeatherPopover: View {
    let data: SharedWeatherService.WeatherData?
    let city: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = data {
                let tempSym = data.units.temperatureSymbol
                HStack {
                    Image(systemName: data.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(data.iconColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(data.temperature)\(tempSym)")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                        Text(data.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.blue)
                    Text(city)
                        .font(.subheadline)
                }

                HStack(spacing: 16) {
                    Label("\(data.feelsLike)\(tempSym)", systemImage: "thermometer.medium")
                    Label("\(data.windSpeed) \(data.units.windSpeedLabel)", systemImage: "wind")
                    Label("\(data.humidity)%", systemImage: "humidity.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Loading weather...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

// MARK: - Image Prefetcher (Shared Singleton)

@MainActor
final class ImagePrefetcher: ObservableObject {
    static let shared = ImagePrefetcher()

    @Published private(set) var loadedCount = 0

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlightURLs = Set<URL>()
    private var failedURLs = Set<URL>()
    private let queue = DispatchQueue(label: "imagePrefetcher", qos: .userInitiated)

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100_000_000
    }

    func prefetch(urls: [URL]) {
        for url in urls {
            let shouldLoad = queue.sync { () -> Bool in
                guard !inFlightURLs.contains(url),
                      !failedURLs.contains(url),
                      cache.object(forKey: url as NSURL) == nil else { return false }
                inFlightURLs.insert(url)
                return true
            }
            guard shouldLoad else { continue }

            Task.detached(priority: .utility) { [weak self] in
                await self?.fetchImage(url: url)
            }
        }
    }

    private func fetchImage(url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = NSImage(data: data) {
                queue.sync {
                    self.cache.setObject(image, forKey: url as NSURL, cost: data.count)
                    _ = self.inFlightURLs.remove(url)
                }
                await MainActor.run {
                    self.loadedCount += 1
                }
            } else {
                queue.sync {
                    self.failedURLs.insert(url)
                    _ = self.inFlightURLs.remove(url)
                }
            }
        } catch {
            queue.sync {
                _ = self.inFlightURLs.remove(url)
            }
        }
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func clearCache() {
        cache.removeAllObjects()
        queue.sync {
            inFlightURLs.removeAll()
            failedURLs.removeAll()
        }
        loadedCount = 0
    }

    func hasFailed(_ url: URL) -> Bool {
        queue.sync { failedURLs.contains(url) }
    }

    func isLoading(_ url: URL) -> Bool {
        queue.sync { inFlightURLs.contains(url) }
    }

    func loadImage(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if hasFailed(url) { return nil }

        let alreadyLoading = queue.sync { inFlightURLs.contains(url) }
        if alreadyLoading {
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if let cached = cache.object(forKey: url as NSURL) {
                    return cached
                }
                if !isLoading(url) { break }
            }
            return cache.object(forKey: url as NSURL)
        }

        let didStart = queue.sync { () -> Bool in
            guard !inFlightURLs.contains(url) else { return false }
            inFlightURLs.insert(url)
            return true
        }

        guard didStart else {
            return cache.object(forKey: url as NSURL)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            queue.sync { _ = inFlightURLs.remove(url) }

            if let image = NSImage(data: data) {
                queue.sync {
                    cache.setObject(image, forKey: url as NSURL, cost: data.count)
                }
                loadedCount += 1
                return image
            } else {
                queue.sync { _ = failedURLs.insert(url) }
            }
        } catch {
            queue.sync { _ = inFlightURLs.remove(url) }
        }
        return nil
    }
}

// MARK: - Masonry Grid Layout

struct MasonryGrid<Content: View>: View {
    let columns: Int
    let spacing: CGFloat
    let content: Content

    init(columns: Int, spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        MasonryLayout(columns: columns, spacing: spacing) {
            content
        }
    }
}

struct MasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    struct CacheData {
        var sizes: [CGSize] = []
        var positions: [CGPoint] = []
        var totalSize: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> CacheData {
        CacheData()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let width = proposal.width ?? 800
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        var sizes: [CGSize] = []
        var positions: [CGPoint] = []

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            sizes.append(size)

            let x = CGFloat(shortestColumn) * (columnWidth + spacing)
            let y = columnHeights[shortestColumn]
            positions.append(CGPoint(x: x, y: y))

            columnHeights[shortestColumn] += size.height + spacing
        }

        let maxHeight = columnHeights.max() ?? 0
        let totalSize = CGSize(width: width, height: max(0, maxHeight - spacing))

        cache.sizes = sizes
        cache.positions = positions
        cache.totalSize = totalSize

        return totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        let columnWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        guard cache.positions.count == subviews.count else {
            var columnHeights = Array(repeating: CGFloat(0), count: columns)
            for (_, subview) in subviews.enumerated() {
                let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
                let x = bounds.minX + CGFloat(shortestColumn) * (columnWidth + spacing)
                let y = bounds.minY + columnHeights[shortestColumn]
                let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: columnWidth, height: size.height))
                columnHeights[shortestColumn] += size.height + spacing
            }
            return
        }

        for (index, subview) in subviews.enumerated() {
            let position = cache.positions[index]
            let size = cache.sizes[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(width: columnWidth, height: size.height)
            )
        }
    }
}

#Preview {
    Text("Cards View")
}
