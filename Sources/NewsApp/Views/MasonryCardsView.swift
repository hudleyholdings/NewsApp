import SwiftUI

struct MasonryCardsView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Binding var isPresented: Bool
    @State private var selectedArticle: Article?
    @State private var showReader = false
    @State private var isReaderExpanded = false
    private let imagePrefetcher = ImagePrefetcher.shared

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
        .focusable()
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onChange(of: showReader) { _, new in
            if !new {
                selectedArticle = nil
                feedStore.selectedArticleID = nil
            }
        }
        .task {
            prefetchImages()
            await feedStore.discoverImages(for: allSortedArticles)
        }
    }

    // MARK: - Cards Content

    private var cardsContent: some View {
        GeometryReader { geo in
            let columns = columnCount(for: geo.size.width)
            let padding: CGFloat = geo.size.width > 1200 ? 48 : (geo.size.width > 800 ? 32 : 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Newspaper Masthead
                    mastheadView
                        .padding(.horizontal, padding)
                        .padding(.top, 20)

                    // Lead story section
                    let allArticles = allSortedArticles
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
                    let groupedArticles = articlesGroupedByCategory

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
        case .radioBrowse, .radioStation, .radioCategory, .radioFavorites:
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
                // Lead image
                if let url = article.imageURL {
                    LeadImageView(url: url)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .clipped()
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
            HStack(alignment: .top, spacing: 12) {
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

                // Small thumbnail
                if let url = article.imageURL {
                    SmallImageView(url: url)
                        .frame(width: 72, height: 72)
                        .clipped()
                }
            }
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
                ForEach(articles.prefix(12)) { article in
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

    private var articleCount: Int {
        feedStore.sortedArticles(for: feedStore.selectedSidebarItem).count
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: Date())
    }

    private var allSortedArticles: [Article] {
        let sorted = feedStore.sortedArticles(for: feedStore.selectedSidebarItem)
        var seen = Set<String>()
        return sorted.compactMap { a in
            let key = a.link?.absoluteString ?? a.externalID
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return a
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

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTime(for article: Article) -> String? {
        guard let date = article.publishedAt else { return nil }
        return Self.timeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var articlesGroupedByCategory: [(category: String, articles: [Article])] {
        let articles = allSortedArticles

        // Skip the first 4 (used in lead section)
        let remaining = Array(articles.dropFirst(4))

        var grouped = [String: [Article]]()
        for article in remaining {
            let category = feedStore.feedCategory(for: article.feedID)
                ?? feedStore.feedName(for: article.feedID)
                ?? "Other"
            grouped[category, default: []].append(article)
        }

        return grouped
            .sorted { $0.value.count > $1.value.count }
            .map { ($0.key, Array($0.value.prefix(12))) }
    }
}

// MARK: - Lead Image View

private struct LeadImageView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.06))
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView().controlSize(.small)
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
            // Image (sharp corners, no rounding)
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
                .frame(height: 180)
                .clipped()
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
                .stroke(.primary.opacity(isHovered ? 0.15 : 0.06), lineWidth: 1)
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
                            .lineLimit(1)
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
                .help(weather.current.map { "\($0.description) in \($0.city)\n\($0.temperature)°F • Feels like \($0.feelsLike)°F" } ?? "Weather")
                .popover(isPresented: $showingPopover) {
                    CardsWeatherPopover(data: weather.current, city: displayCity)
                }
                .task {
                    weather.configure(
                        city: displayCity,
                        lat: settings.weatherLatitude,
                        lon: settings.weatherLongitude
                    )
                    weather.fetchIfNeeded()
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
                HStack {
                    Image(systemName: data.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(data.iconColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(data.temperature)°F")
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
                    Label("\(data.feelsLike)°", systemImage: "thermometer.medium")
                    Label("\(data.windSpeed) mph", systemImage: "wind")
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
                    self.inFlightURLs.remove(url)
                }
                await MainActor.run {
                    self.loadedCount += 1
                }
            } else {
                queue.sync {
                    self.failedURLs.insert(url)
                    self.inFlightURLs.remove(url)
                }
            }
        } catch {
            queue.sync {
                self.inFlightURLs.remove(url)
            }
        }
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
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
            queue.sync { inFlightURLs.remove(url) }

            if let image = NSImage(data: data) {
                queue.sync {
                    cache.setObject(image, forKey: url as NSURL, cost: data.count)
                }
                loadedCount += 1
                return image
            } else {
                queue.sync { failedURLs.insert(url) }
            }
        } catch {
            queue.sync { inFlightURLs.remove(url) }
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
