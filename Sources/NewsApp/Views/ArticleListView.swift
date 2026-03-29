import SwiftUI
import AppKit

struct ArticleListView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var visibleCount = 120

    var body: some View {
        VStack(spacing: 0) {
            // Polymarket sort picker bar
            if let polymarketFeed = selectedPolymarketFeed {
                HStack {
                    Image(systemName: "chart.pie")
                        .foregroundStyle(.purple)
                    Text("Polymarket")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("Sort:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    PolymarketSortPicker(feed: polymarketFeed)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
                Divider()
            }

            // Main list
            Group {
                if settings.articleListStyle == .newspaper {
                    listView.listStyle(.plain).modifier(HardScrollEdgeModifier())
                } else {
                    listView.listStyle(.inset).modifier(HardScrollEdgeModifier())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if filteredArticles.isEmpty {
                ContentUnavailableView("No Articles", systemImage: "newspaper", description: Text("Refresh to load the latest stories."))
            }
        }
    }

    private var selectedPolymarketFeed: Feed? {
        guard case .feed(let feedID) = feedStore.selectedSidebarItem else { return nil }
        return feedStore.polymarketFeed(for: feedID)
    }

    private var listView: some View {
        let articles = visibleArticles
        let lastID = articles.last?.id
        let showSource = feedStore.selectedSidebarItem?.listID != nil
        return ScrollViewReader { proxy in
        List(selection: $feedStore.selectedArticleID) {
            if settings.articleListStyle == .newspaper {
                ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                    ArticleRow(article: article, feedName: feedStore.feedName(for: article.feedID), isLead: index == 0, style: .newspaper, showSource: showSource)
                        .id(article.id)
                        .tag(Optional(article.id))
                        .onAppear { loadMoreIfNeeded(currentID: article.id, lastID: lastID) }
                        .contextMenu {
                            Button(article.isRead ? "Mark Unread" : "Mark Read") {
                                feedStore.markRead(article, isRead: !article.isRead)
                            }
                            Button(article.isStarred ? "Unstar" : "Star") {
                                feedStore.toggleStar(article)
                            }
                            if let link = article.link {
                                Button("Open in Browser") {
                                    NSWorkspace.shared.open(link)
                                }
                            }
                        }
                }
            } else {
                ForEach(articles) { article in
                    ArticleRow(article: article, feedName: feedStore.feedName(for: article.feedID), isLead: false, style: .standard, showSource: showSource)
                        .id(article.id)
                        .tag(Optional(article.id))
                        .onAppear { loadMoreIfNeeded(currentID: article.id, lastID: lastID) }
                        .contextMenu {
                            Button(article.isRead ? "Mark Unread" : "Mark Read") {
                                feedStore.markRead(article, isRead: !article.isRead)
                            }
                            Button(article.isStarred ? "Unstar" : "Star") {
                                feedStore.toggleStar(article)
                            }
                            if let link = article.link {
                                Button("Open in Browser") {
                                    NSWorkspace.shared.open(link)
                                }
                            }
                        }
                }
            }
        }
        .id(feedStore.selectedSidebarItem)
        .onChange(of: feedStore.selectedSidebarItem) { _, _ in
            visibleCount = 120
        }
        .onChange(of: feedStore.searchText) { _, _ in
            visibleCount = 120
        }
        .onChange(of: feedStore.selectedArticleID) { _, newValue in
            if let newValue {
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .frame(maxHeight: .infinity)
        } // ScrollViewReader
    }

    private var filteredArticles: [Article] {
        let base = feedStore.sortedArticles(for: feedStore.selectedSidebarItem)
        let query = feedStore.searchText
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            ($0.summary?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var visibleArticles: [Article] {
        let filtered = filteredArticles
        if filtered.count <= visibleCount { return filtered }
        return Array(filtered.prefix(visibleCount))
    }

    private func loadMoreIfNeeded(currentID: UUID, lastID: UUID?) {
        guard let lastID, currentID == lastID else { return }
        if visibleCount < filteredArticles.count {
            visibleCount += 80
        }
    }
}

struct ArticleRow: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    let article: Article
    let feedName: String?
    let isLead: Bool
    let style: ArticleListStyle
    let showSource: Bool

    var body: some View {
        let condensed = style == .newspaper && settings.listDensity == .compact
        let isSelected = feedStore.selectedArticleID == article.id
        let metaSize = max(settings.articleMetaSize, settings.articleTitleSize * 0.72)
        let metaFont = settings.listFont(size: metaSize)

        // Use special display for Polymarket articles
        if article.isPolymarketArticle {
            polymarketRow(isSelected: isSelected, metaFont: metaFont)
        } else {
            standardRow(condensed: condensed, isSelected: isSelected, metaSize: metaSize, metaFont: metaFont)
        }
    }

    @ViewBuilder
    private func polymarketRow(isSelected: Bool, metaFont: Font) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // Unread indicator column - fixed width, dot centered vertically
            ZStack(alignment: .trailing) {
                Color.clear
                    .frame(width: 14)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(article.isRead ? 0 : 1)
                    .padding(.trailing, 4)
            }

            // Probability badge - compact colored badge
            if let data = article.polymarketData {
                Text("\(data.probabilityPercent)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(probabilityColor(data.probability))
                    )
                    .padding(.trailing, 10)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(settings.listFont(size: settings.articleTitleSize, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(article.isRead ? .secondary : .primary)

                // Stats row with leading label for multi-outcome
                VStack(alignment: .leading, spacing: 4) {
                    if let data = article.polymarketData {
                        // Show leading outcome label for multi-outcome markets
                        if data.isMultiOutcome, let label = data.leadingLabel, !label.isEmpty {
                            Text(label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(red: 0.55, green: 0.5, blue: 0.65))  // Muted purple
                                .lineLimit(nil)
                        }

                        HStack(spacing: 8) {
                            Label(data.formattedVolume24hr, systemImage: "chart.line.uptrend.xyaxis")
                                .font(metaFont)
                                .foregroundStyle(.secondary)

                            if let timeLeft = data.timeRemaining {
                                Label(timeLeft, systemImage: "clock")
                                    .font(metaFont)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if article.isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
    }

    private func probabilityColor(_ probability: Double) -> Color {
        let percent = probability * 100
        if percent >= 60 {
            return Color(red: 0.2, green: 0.7, blue: 0.4)  // Muted green
        } else if percent >= 35 {
            return Color(red: 0.55, green: 0.55, blue: 0.6)  // Slate gray
        } else {
            return Color(red: 0.6, green: 0.45, blue: 0.45)  // Muted red-gray
        }
    }

    @ViewBuilder
    private func standardRow(condensed: Bool, isSelected: Bool, metaSize: CGFloat, metaFont: Font) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Unread indicator column - fixed width, dot aligned with first line of headline
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .frame(width: 14)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(article.isRead ? 0 : 1)
                    .padding(.top, 7)
                    .padding(.trailing, 4)
            }

            // Main content - cleanly left aligned
            VStack(alignment: .leading, spacing: condensed ? 4 : 6) {
                Text(headlineText)
                    .font(headlineFont)
                    .textCase(condensed ? .uppercase : nil)
                    .foregroundStyle(article.isRead ? .secondary : .primary)

                if showSummary, let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(settings.listFont(size: settings.articleSummarySize))
                        .foregroundStyle(.secondary)
                        .lineLimit(settings.listDensity.summaryLines)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        if let source = sourceText {
                            MetaPill(text: source, font: metaFont)
                        }
                        if let author = article.author, !author.isEmpty, !condensed {
                            Text(author)
                                .font(metaFont)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }
                    if hasPublishedDate {
                        HStack(spacing: 6) {
                            Text(relativeTime)
                                .monospacedDigit()
                            if !condensed {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(absoluteTime)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(metaFont)
                    }
                }
            }

            Spacer(minLength: 8)

            if article.isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, settings.listDensity == .comfortable ? 8 : 4)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    private var headlineText: String {
        if style == .newspaper && settings.listDensity == .compact {
            return article.title.uppercased()
        }
        return article.title
    }

    private var headlineFont: Font {
        let baseSize = settings.articleTitleSize + (style == .newspaper ? (isLead ? 6 : 2) : 0)
        let weight: Font.Weight = style == .newspaper ? (isLead ? .bold : .semibold) : .semibold
        return settings.listFont(size: baseSize, weight: weight)
    }

    private var showSummary: Bool {
        if style == .newspaper {
            return settings.listDensity == .comfortable && isLead
        }
        return true
    }

    private var sourceText: String? {
        if showSource, let feedName = feedName {
            return feedName
        }
        return article.link?.host ?? feedName
    }

    private var relativeTime: String {
        guard let date = article.publishedAt else { return "" }
        return ArticleRow.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var absoluteTime: String {
        guard let date = article.publishedAt else { return "" }
        return ArticleRow.absoluteFormatter.string(from: date)
    }

    private var hasPublishedDate: Bool {
        article.publishedAt != nil
    }

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter = RelativeDateTimeFormatter()
}

private struct HardScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}

private struct MetaPill: View {
    let text: String
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}

// MARK: - Polymarket Sort Picker

struct PolymarketSortPicker: View {
    @EnvironmentObject private var feedStore: FeedStore
    let feed: Feed

    private var currentSort: PolymarketSort {
        feed.polymarketConfig?.sort ?? .volume24hr
    }

    private var isLoading: Bool {
        feedStore.polymarketLoadingFeedID == feed.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Section("Sort By") {
                    ForEach(PolymarketSort.allCases) { sort in
                        Button {
                            feedStore.updatePolymarketSort(feedID: feed.id, sort: sort)
                        } label: {
                            HStack {
                                Text(sort.label)
                                if currentSort == sort {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(currentSort.label)
                }
                .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}
