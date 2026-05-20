import SwiftUI

struct FeedListView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var radioStore = RadioStore.shared
    @StateObject private var radioPlayer = RadioPlayer.shared
    @State private var feedToEdit: Feed?
    @State private var showingEditSheet = false

    var body: some View {
        VStack(spacing: 0) {
            SidebarControlBar(allCategoryNames: Array(groupedFeeds.keys))
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
            ScrollViewReader { proxy in
            List(selection: $feedStore.selectedSidebarItem) {
                Section("Lists") {
                    let allSelected = feedStore.selectedSidebarItem == .list(FeedStore.allFeedsID)
                    ListEntryRow(
                        listID: FeedStore.allFeedsID,
                        title: "All Feeds",
                        subtitle: "Everything",
                        iconSystemName: "tray.full",
                        iconURL: nil
                    )
                    .tag(Optional(SidebarSelection.list(FeedStore.allFeedsID)))
                    .id(SidebarSelection.list(FeedStore.allFeedsID))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        feedStore.selectedSidebarItem = .list(FeedStore.allFeedsID)
                    }
                    .listRowBackground(allSelected ? Color.accentColor.opacity(0.25) : Color.clear)

                    let unreadSelected = feedStore.selectedSidebarItem == .list(FeedStore.unreadID)
                    ListEntryRow(
                        listID: FeedStore.unreadID,
                        title: "Unread",
                        subtitle: "Only unread articles",
                        iconSystemName: "circle.inset.filled",
                        iconURL: nil
                    )
                    .tag(Optional(SidebarSelection.list(FeedStore.unreadID)))
                    .id(SidebarSelection.list(FeedStore.unreadID))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        feedStore.selectedSidebarItem = .list(FeedStore.unreadID)
                    }
                    .listRowBackground(unreadSelected ? Color.accentColor.opacity(0.25) : Color.clear)

                    let bookmarksSelected = feedStore.selectedSidebarItem == .list(FeedStore.favoritesID)
                    ListEntryRow(
                        listID: FeedStore.favoritesID,
                        title: "Bookmarks",
                        subtitle: "Saved stories",
                        iconSystemName: "bookmark.fill",
                        iconURL: nil,
                        showBookmarkCount: true
                    )
                    .tag(Optional(SidebarSelection.list(FeedStore.favoritesID)))
                    .id(SidebarSelection.list(FeedStore.favoritesID))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        feedStore.selectedSidebarItem = .list(FeedStore.favoritesID)
                    }
                    .listRowBackground(bookmarksSelected ? Color.accentColor.opacity(0.25) : Color.clear)

                    ForEach(feedStore.lists) { list in
                        let isSelected = feedStore.selectedSidebarItem == .list(list.id)
                        ListEntryRow(
                            listID: list.id,
                            title: list.name,
                            subtitle: list.feedIDs.isEmpty ? "No feeds" : "\(list.feedIDs.count) feeds",
                            iconSystemName: nil,
                            iconURL: list.iconURL
                        )
                        .tag(Optional(SidebarSelection.list(list.id)))
                        .id(SidebarSelection.list(list.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            feedStore.selectedSidebarItem = .list(list.id)
                        }
                        .listRowBackground(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                    }
                }

                ForEach(sortedCategories, id: \.self) { category in
                    Section {
                        let categorySelected = feedStore.selectedSidebarItem == .category(category)
                        CategoryHeader(
                            category: category,
                            isSelected: categorySelected,
                            isCollapsed: settings.collapsedCategories.contains(category),
                            onToggleCollapse: { settings.toggleCategoryCollapsed(category) }
                        )
                        .tag(Optional(SidebarSelection.category(category)))
                        .id(SidebarSelection.category(category))
                        .onTapGesture {
                            feedStore.selectedSidebarItem = .category(category)
                        }
                        .listRowBackground(categorySelected ? Color.accentColor.opacity(0.25) : Color.clear)

                        if !settings.collapsedCategories.contains(category) {
                        ForEach(visibleFeeds(in: category)) { feed in
                            let isSelected = feedStore.selectedSidebarItem == .feed(feed.id)
                            FeedRow(
                                feed: feed,
                                isSelected: isSelected
                            )
                            .tag(Optional(SidebarSelection.feed(feed.id)))
                            .id(SidebarSelection.feed(feed.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                feedStore.selectedSidebarItem = .feed(feed.id)
                            }
                            .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                            .contextMenu {
                                Button {
                                    feedStore.markAllAsRead(for: .feed(feed.id))
                                } label: {
                                    Label("Mark All as Read", systemImage: "checkmark.circle")
                                }

                                Button {
                                    feedToEdit = feed
                                    showingEditSheet = true
                                } label: {
                                    Label("Edit Feed", systemImage: "pencil")
                                }

                                if !feedStore.lists.isEmpty {
                                    Menu("Add to List") {
                                        ForEach(feedStore.lists) { list in
                                            Button(list.name) {
                                                feedStore.addFeed(feed.id, toList: list.id)
                                            }
                                        }
                                    }
                                }

                                Divider()

                                Button {
                                    feedStore.toggleFeedEnabled(feed)
                                } label: {
                                    Label(feed.isEnabled ? "Disable Feed" : "Enable Feed",
                                          systemImage: feed.isEnabled ? "pause.circle" : "play.circle")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    feedStore.deleteFeed(id: feed.id)
                                } label: {
                                    Label("Delete Feed", systemImage: "trash")
                                }
                            }
                        }
                        }
                    }
                }

                // MARK: - Radio Section (News/Talk only)
                if settings.radioEnabled {
                    Section("Radio") {
                        // Browse All News/Talk stations
                        let newsStationCount = radioStore.newsTalkStations.count
                        let radioBrowseSelected = feedStore.selectedSidebarItem == .radioBrowse
                        MediaSectionRow(
                            title: "News & Talk",
                            subtitle: "\(newsStationCount) stations",
                            count: newsStationCount,
                            icon: "radio.fill",
                            isSelected: radioBrowseSelected
                        )
                        .tag(Optional(SidebarSelection.radioBrowse))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            feedStore.selectedSidebarItem = .radioBrowse
                        }
                        .listRowBackground(radioBrowseSelected ? Color.accentColor.opacity(0.25) : Color.clear)

                        // Favorites
                        if !radioStore.favorites.isEmpty {
                            let radioFavSelected = feedStore.selectedSidebarItem == .radioFavorites
                            MediaSectionRow(
                                title: "Favorites",
                                subtitle: "Your saved stations",
                                count: radioStore.favorites.count,
                                icon: "star.fill",
                                isSelected: radioFavSelected
                            )
                            .tag(Optional(SidebarSelection.radioFavorites))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                feedStore.selectedSidebarItem = .radioFavorites
                            }
                            .listRowBackground(radioFavSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                        }
                    }
                }

            }
            .listStyle(.sidebar)
            .modifier(HardScrollEdgeModifier())
            .frame(maxHeight: .infinity)
            .onChange(of: feedStore.selectedSidebarItem) { _, newValue in
                if let newValue {
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
            } // ScrollViewReader

            // Pinned Now Playing mini player at bottom
            if let station = radioPlayer.currentStation {
                Divider()
                SidebarMiniPlayer(station: station, isPlaying: radioPlayer.isPlaying)
            }
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .sheet(isPresented: $showingEditSheet) {
            if let feed = feedToEdit {
                EditFeedSheet(feed: feed, isPresented: $showingEditSheet)
            }
        }
    }

    /// All feeds grouped by category. Sort within a category is handled in
    /// `visibleFeeds(in:)` so it can respond to the live sort-mode setting.
    private var groupedFeeds: [String: [Feed]] {
        Dictionary(grouping: feedStore.feeds, by: { $0.category ?? "Other" })
    }

    /// Categories that should appear in the sidebar — filtered if the user toggled the
    /// "show only with unread" filter on, then sorted per the chosen sort mode.
    private var sortedCategories: [String] {
        let visible = groupedFeeds.keys.filter { category in
            if !settings.sidebarFilterUnreadOnly { return true }
            return categoryUnreadCount(category) > 0
        }

        switch settings.sidebarSortMode {
        case .alphabetical:
            return visible.sorted { cat1, cat2 in
                let isSports1 = cat1.lowercased().contains("sport")
                let isSports2 = cat2.lowercased().contains("sport")
                if isSports1 && !isSports2 { return false }
                if !isSports1 && isSports2 { return true }
                return cat1 < cat2
            }
        case .byUnreadCount:
            return visible.sorted { cat1, cat2 in
                let a = categoryUnreadCount(cat1)
                let b = categoryUnreadCount(cat2)
                if a != b { return a > b }
                return cat1 < cat2
            }
        }
    }

    /// Feeds inside a category after applying the unread filter and the chosen sort.
    private func visibleFeeds(in category: String) -> [Feed] {
        var feeds = groupedFeeds[category] ?? []
        if settings.sidebarFilterUnreadOnly {
            feeds = feeds.filter { feedStore.feedBadgeCount(for: $0.id, mode: .unread) > 0 }
        }
        switch settings.sidebarSortMode {
        case .alphabetical:
            return feeds.sorted { $0.name < $1.name }
        case .byUnreadCount:
            return feeds.sorted { a, b in
                let aCount = feedStore.feedBadgeCount(for: a.id, mode: .unread)
                let bCount = feedStore.feedBadgeCount(for: b.id, mode: .unread)
                if aCount != bCount { return aCount > bCount }
                return a.name < b.name
            }
        }
    }

    private func categoryUnreadCount(_ category: String) -> Int {
        (groupedFeeds[category] ?? []).reduce(0) { partial, feed in
            partial + feedStore.feedBadgeCount(for: feed.id, mode: .unread)
        }
    }
}

// MARK: - Sidebar Control Bar (Filter + Sort + Expand/Collapse)

private struct SidebarControlBar: View {
    @EnvironmentObject private var settings: SettingsStore
    /// Every category currently present in the sidebar — used by "Collapse All" so we
    /// know which names to insert into the collapsed-set.
    let allCategoryNames: [String]

    var body: some View {
        HStack(spacing: 4) {
            FilterToggleChip(isOn: $settings.sidebarFilterUnreadOnly)

            SortMenuButton(sortMode: $settings.sidebarSortMode)

            // Single labeled toggle. While any category is collapsed the chip offers to
            // expand them all; once everything is expanded it flips to "Collapse all".
            let anyCollapsed = !settings.collapsedCategories
                .intersection(Set(allCategoryNames)).isEmpty
            ExpandCollapseChip(anyCollapsed: anyCollapsed) {
                if anyCollapsed {
                    settings.expandAllCategories()
                } else {
                    settings.collapseAllCategories(allCategoryNames)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ExpandCollapseChip: View {
    let anyCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: anyCollapsed
                      ? "rectangle.expand.vertical"
                      : "rectangle.compress.vertical")
                    .font(.system(size: 12, weight: .medium))
                Text(anyCollapsed ? "Expand all" : "Collapse all")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(anyCollapsed ? "Expand all categories" : "Collapse all categories")
    }
}

/// A labelled chip-style toggle so the action ("show only unread") is obvious without
/// requiring the user to click and observe the effect.
private struct FilterToggleChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("Unread only")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isOn ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(isOn
              ? "Showing only feeds with unread articles — click to show all"
              : "Show only feeds with unread articles")
    }
}

private struct SortMenuButton: View {
    @Binding var sortMode: SidebarSortMode

    var body: some View {
        Menu {
            Picker("Sort by", selection: $sortMode) {
                ForEach(SidebarSortMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                Text("Sort")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort feeds and categories")
    }
}

private struct SidebarIconButton: View {
    let systemName: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(tooltip)
    }
}

struct CategoryHeader: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let category: String
    let isSelected: Bool
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void

    var body: some View {
        let count = feedStore.categoryBadgeCount(for: category, mode: settings.badgeCountMode)
        let chevronColor: Color = isSelected
            ? SidebarRowColors.title(for: colorScheme)
            : .secondary
        HStack(spacing: 8) {
            Button(action: onToggleCollapse) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(chevronColor)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(isCollapsed ? "Expand \(category)" : "Collapse \(category)")
            // The chevron and the category-select tap-gesture share the row; this
            // higher-priority gesture keeps chevron clicks from also selecting the
            // category.
            .onTapGesture {
                onToggleCollapse()
            }

            Text(category)
                .font(settings.listFont(size: settings.feedTitleSize - 1, weight: .semibold))
                // When the row is selected the listRowBackground paints accent — use
                // the high-contrast label color so the title stays readable. Unselected
                // categories keep the muted secondary tone that distinguishes them
                // visually from feeds.
                .foregroundStyle(isSelected ? SidebarRowColors.title(for: colorScheme) : Color.secondary)
            Spacer(minLength: 4)
            SidebarCountBadge(
                count: count,
                isSelected: isSelected,
                selectedBackground: Color.accentColor.opacity(0.3)
            )
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct FeedRow: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let feed: Feed
    let isSelected: Bool

    var body: some View {
        let titleColor = SidebarRowColors.title(for: colorScheme)
        let count = feedStore.feedBadgeCount(for: feed.id, mode: settings.badgeCountMode)
        HStack(spacing: 8) {
            FeedIconView(iconURL: feed.iconURL, siteURL: feed.siteURL ?? feed.feedURL, fallbackText: feed.name)
            Text(feed.name)
                .font(settings.listFont(size: settings.feedTitleSize, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            SidebarCountBadge(count: count)
        }
        .opacity(feed.isEnabled ? 1 : 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(feed.name)
    }
}

private struct FeedIconView: View {
    let iconURL: URL?
    let siteURL: URL?
    let fallbackText: String

    var body: some View {
        if let iconURL {
            AsyncImage(url: iconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                FaviconView(url: siteURL, fallbackText: fallbackText)
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            FaviconView(url: siteURL, fallbackText: fallbackText)
        }
    }
}

struct ListEntryRow: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let listID: UUID
    let title: String
    let subtitle: String
    let iconSystemName: String?
    let iconURL: URL?
    var showBookmarkCount: Bool = false

    var body: some View {
        let titleColor = SidebarRowColors.title(for: colorScheme)
        // For bookmarks, always show total count; for other lists, use badge mode
        let count = showBookmarkCount
            ? feedStore.favoritesArticles().count
            : feedStore.listBadgeCount(for: listID, mode: settings.badgeCountMode)
        HStack(spacing: 8) {
            ListIconView(name: title, iconSystemName: iconSystemName, iconURL: iconURL)
            Text(title)
                .font(settings.listFont(size: settings.feedTitleSize, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            SidebarCountBadge(count: count, semanticLabel: semanticBadgeLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(title)
    }

    /// Tooltip label for the badge on the three smart-list rows. nil for user-created lists,
    /// which keep the existing mode-aware tooltip.
    private var semanticBadgeLabel: String? {
        if listID == FeedStore.allFeedsID {
            return "Total stories across all feeds"
        }
        if listID == FeedStore.unreadID {
            return "Unread articles"
        }
        if showBookmarkCount {
            return "Bookmarked articles"
        }
        return nil
    }
}

private enum SidebarRowMetrics {
    /// Minimum reserved width for the badge column so single-digit and four-digit counts
    /// share a consistent visual column. Wider numbers (e.g. comma-formatted 10,100+)
    /// expand the capsule leftward via `minWidth`, keeping the trailing edge aligned.
    static let badgeColumnMinWidth: CGFloat = 44
}

private struct SidebarCountBadge: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let count: Int
    var isSelected: Bool = false
    var selectedBackground: Color? = nil
    /// When set, this label is shown in the hover tooltip in place of the mode-derived
    /// default. Used by smart-list rows (All Feeds = total, Unread, Bookmarks) whose
    /// badge semantics don't match the user-controlled `BadgeCountMode`.
    var semanticLabel: String? = nil

    var body: some View {
        let badgeTextColor = SidebarRowColors.badgeText(for: colorScheme)
        let backgroundColor: Color

        if count > 0 {
            if isSelected, let selectedBackground {
                backgroundColor = selectedBackground
            } else if semanticLabel != nil {
                // Smart-list badges always use the neutral background — they're not
                // tied to the "new since X" accent treatment.
                backgroundColor = SidebarRowColors.badgeBackground(for: colorScheme)
            } else {
                // Use a subtle accent color for "new" modes to differentiate from unread
                switch settings.badgeCountMode {
                case .unread:
                    backgroundColor = SidebarRowColors.badgeBackground(for: colorScheme)
                case .newSinceSession, .newSinceRefresh:
                    backgroundColor = Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.15)
                }
            }
        } else {
            backgroundColor = .clear
        }

        let tooltipText: String = {
            if let semanticLabel {
                return count == 0 ? semanticLabel : "\(count.formatted(.number)) \u{2014} \(semanticLabel)"
            }
            if count == 0 {
                switch settings.badgeCountMode {
                case .unread: return "All read"
                case .newSinceSession: return "No new articles this session"
                case .newSinceRefresh: return "No new articles since refresh"
                }
            }
            return "\(count) \(settings.badgeCountMode.shortLabel)"
        }()

        return Text(count, format: .number)
            .font(.caption2)
            .foregroundStyle(count > 0 ? badgeTextColor : .clear)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(count > 0 ? backgroundColor : .clear)
            .clipShape(Capsule())
            .frame(minWidth: SidebarRowMetrics.badgeColumnMinWidth, alignment: .trailing)
            .help(tooltipText)
    }
}

private enum SidebarRowColors {
    static func title(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(.labelColor).opacity(0.95)
        default:
            return Color(.labelColor)
        }
    }

    static func badgeText(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(.labelColor).opacity(0.85)
        default:
            return Color(.secondaryLabelColor)
        }
    }

    static func badgeBackground(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color(.tertiarySystemFill)
        }
    }
}

// MARK: - Edit Feed Sheet

// MARK: - Media Section Helper Views

struct MediaSectionRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let count: Int
    let icon: String
    let isSelected: Bool

    var body: some View {
        let titleColor = SidebarRowColors.title(for: colorScheme)
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(settings.listFont(size: settings.feedTitleSize, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Text(subtitle)
                    .font(settings.listFont(size: settings.feedSubtitleSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            SidebarCountBadge(count: count)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sidebar Mini Player (Pinned to Bottom)

struct SidebarMiniPlayer: View {
    @StateObject private var radioPlayer = RadioPlayer.shared
    @EnvironmentObject private var feedStore: FeedStore
    let station: RadioStation
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button {
                radioPlayer.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 36, height: 36)

                    if radioPlayer.isBuffering {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.borderless)

            // Station info (tappable to navigate)
            Button {
                feedStore.selectedSidebarItem = .radioStation(station.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if isPlaying {
                            Image(systemName: "waveform")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.accentColor)
                                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
                        }
                        Text(isPlaying ? "Playing" : "Paused")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.borderless)

            Spacer()

            // Stop button
            Button {
                radioPlayer.stop()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Stop")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct MediaCategoryHeader: View {
    @EnvironmentObject private var settings: SettingsStore
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            Text(title)
                .font(settings.listFont(size: settings.feedTitleSize - 1, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            Spacer(minLength: 4)
            SidebarCountBadge(
                count: count,
                isSelected: isSelected,
                selectedBackground: Color.accentColor.opacity(0.3)
            )
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediaCategoryRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        let titleColor = SidebarRowColors.title(for: colorScheme)
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
            Text(title)
                .font(settings.listFont(size: settings.feedTitleSize, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : titleColor)
                .lineLimit(1)
            Spacer(minLength: 4)
            SidebarCountBadge(count: count)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Edit Feed Sheet

private struct HardScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}

struct EditFeedSheet: View {
    @EnvironmentObject private var feedStore: FeedStore
    let feed: Feed
    @Binding var isPresented: Bool

    @State private var name: String
    @State private var category: String
    @State private var customCategory: String = ""
    @State private var isEnabled: Bool
    @State private var showDeleteConfirmation = false

    private let existingCategories: [String]

    init(feed: Feed, isPresented: Binding<Bool>) {
        self.feed = feed
        self._isPresented = isPresented
        self._name = State(initialValue: feed.name)
        self._category = State(initialValue: feed.category ?? "Other")
        self._isEnabled = State(initialValue: feed.isEnabled)
        self.existingCategories = []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Feed")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("General") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Enabled", isOn: $isEnabled)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(allCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                        Text("New Category...").tag("__new__")
                    }

                    if category == "__new__" {
                        TextField("New category name", text: $customCategory)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Feed Info") {
                    LabeledContent("Type") {
                        Text(feed.sourceKind.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("URL") {
                        Text(feed.feedURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    if let lastUpdated = feed.lastUpdated {
                        LabeledContent("Last Updated") {
                            Text(lastUpdated, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Feed")
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 480)
        .confirmationDialog("Delete Feed?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                feedStore.deleteFeed(id: feed.id)
                isPresented = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(feed.name)\"? This cannot be undone.")
        }
    }

    private var allCategories: [String] {
        var cats = Set(feedStore.feeds.compactMap { $0.category })
        cats.insert("Other")
        return cats.sorted()
    }

    private func save() {
        var updated = feed
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.isEnabled = isEnabled

        if category == "__new__" {
            let newCat = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.category = newCat.isEmpty ? "Other" : newCat
        } else {
            updated.category = category
        }

        feedStore.updateFeed(updated)
        isPresented = false
    }
}
