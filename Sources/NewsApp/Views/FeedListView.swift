import SwiftUI
import AppKit

struct FeedListView: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var radioStore = RadioStore.shared
    @StateObject private var radioPlayer = RadioPlayer.shared
    /// Drives the Edit Feed sheet via `.sheet(item:)` — guarantees the feed is non-nil
    /// when SwiftUI evaluates the sheet's content. Avoids the
    /// `.sheet(isPresented:) { if let … }` race where the sheet could render empty.
    @State private var feedToEdit: Feed?
    @State private var showingSidebarOrderEditor = false

    var body: some View {
        VStack(spacing: 0) {
            SidebarControlBar(
                allCategoryNames: allCategoryNames,
                userListIDs: allUserListIDs,
                onCustomizeOrder: openSidebarOrderEditor
            )
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
            ScrollViewReader { proxy in
            List(selection: $feedStore.selectedSidebarItem) {
                Section {
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

                }

                if settings.sidebarSortMode == .custom {
                    ForEach(orderedCustomSidebarItems) { item in
                        customSidebarItemView(item)
                    }
                } else {
                    ForEach(visibleUserLists) { list in
                        userListSection(list)
                    }

                    ForEach(sortedCategories, id: \.self) { category in
                        categorySection(category)
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

                        // My Stations — only surfaced once the user has added at
                        // least one. The "Add Custom Station" button in the
                        // station list view is the discoverable entry point for
                        // creating the first one.
                        if !radioStore.userStations.isEmpty {
                            let myStationsSelected = feedStore.selectedSidebarItem == .radioUserStations
                            MediaSectionRow(
                                title: "My Stations",
                                subtitle: "Custom streams you added",
                                count: radioStore.userStations.count,
                                icon: "antenna.radiowaves.left.and.right.circle",
                                isSelected: myStationsSelected
                            )
                            .tag(Optional(SidebarSelection.radioUserStations))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                feedStore.selectedSidebarItem = .radioUserStations
                            }
                            .listRowBackground(myStationsSelected ? Color.accentColor.opacity(0.25) : Color.clear)
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
        .sheet(item: $feedToEdit) { feed in
            EditFeedSheet(feed: feed, isPresented: Binding(
                get: { feedToEdit != nil },
                set: { if !$0 { feedToEdit = nil } }
            ))
        }
        .sheet(isPresented: $showingSidebarOrderEditor) {
            SidebarOrderSheet(allCategoryNames: allCategoryNames)
                .environmentObject(feedStore)
                .environmentObject(settings)
        }
    }

    /// All feeds grouped by category. Sort within a category is handled in
    /// `visibleFeeds(in:)` so it can respond to the live sort-mode setting.
    private var groupedFeeds: [String: [Feed]] {
        Dictionary(grouping: feedStore.feeds, by: { $0.category ?? "Other" })
    }

    private var allCategoryNames: [String] {
        Array(groupedFeeds.keys)
    }

    private var allUserListIDs: [UUID] {
        feedStore.lists.map(\.id)
    }

    private var visibleUserLists: [UserList] {
        feedStore.lists.filter { list in
            if !settings.sidebarFilterUnreadOnly { return true }
            return feedStore.listBadgeCount(for: list.id, mode: .unread) > 0
        }
    }

    private var visibleCategoryNames: [String] {
        groupedFeeds.keys.filter { category in
            if !settings.sidebarFilterUnreadOnly { return true }
            return categoryUnreadCount(category) > 0
        }
    }

    private var defaultCustomSidebarItems: [SidebarCustomOrderItem] {
        let listItems = visibleUserLists.map { SidebarCustomOrderItem.list($0.id) }
        let categoryItems = CategorySorting
            .applyCustom(order: settings.customCategoryOrder, to: visibleCategoryNames)
            .map { SidebarCustomOrderItem.category($0) }
        return listItems + categoryItems
    }

    private var orderedCustomSidebarItems: [SidebarCustomOrderItem] {
        CategorySorting.applyCustomSidebarOrder(
            order: settings.customSidebarItemOrder,
            to: defaultCustomSidebarItems
        )
    }

    /// Categories that should appear in the sidebar — filtered if the user toggled the
    /// "show only with unread" filter on, then sorted per the chosen sort mode.
    private var sortedCategories: [String] {
        let visible = visibleCategoryNames

        switch settings.sidebarSortMode {
        case .alphabetical:
            return visible.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        case .byUnreadCount:
            return visible.sorted { cat1, cat2 in
                let a = categoryUnreadCount(cat1)
                let b = categoryUnreadCount(cat2)
                if a != b { return a > b }
                return cat1 < cat2
            }
        case .custom:
            return CategorySorting.applyCustom(order: settings.customCategoryOrder, to: Array(visible))
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
        case .custom:
            // Per-feed custom ordering isn't implemented yet — fall back to
            // alphabetical so the within-a-category order is at least stable.
            return feeds.sorted { $0.name < $1.name }
        }
    }

    /// Feeds inside a user-created list, rendered with the same child-row behavior
    /// as category groups.
    private func visibleFeeds(in list: UserList) -> [Feed] {
        let feedsByID = Dictionary(uniqueKeysWithValues: feedStore.feeds.map { ($0.id, $0) })
        var feeds = list.feedIDs.compactMap { feedsByID[$0] }
        if settings.sidebarFilterUnreadOnly {
            feeds = feeds.filter { feedStore.feedBadgeCount(for: $0.id, mode: .unread) > 0 }
        }

        switch settings.sidebarSortMode {
        case .alphabetical:
            return feeds.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .byUnreadCount:
            return feeds.sorted { a, b in
                let aCount = feedStore.feedBadgeCount(for: a.id, mode: .unread)
                let bCount = feedStore.feedBadgeCount(for: b.id, mode: .unread)
                if aCount != bCount { return aCount > bCount }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        case .custom:
            return feeds.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private func categoryUnreadCount(_ category: String) -> Int {
        (groupedFeeds[category] ?? []).reduce(0) { partial, feed in
            partial + feedStore.feedBadgeCount(for: feed.id, mode: .unread)
        }
    }

    @ViewBuilder
    private func customSidebarItemView(_ item: SidebarCustomOrderItem) -> some View {
        switch item.kind {
        case .list:
            if let id = UUID(uuidString: item.value),
               let list = visibleUserLists.first(where: { $0.id == id }) {
                userListSection(list)
            }
        case .category:
            if visibleCategoryNames.contains(item.value) {
                categorySection(item.value)
            }
        }
    }

    @ViewBuilder
    private func userListSection(_ list: UserList) -> some View {
        Section {
            let isSelected = feedStore.selectedSidebarItem == .list(list.id)
            CategoryHeader(
                category: list.name,
                unreadCount: feedStore.listBadgeCount(for: list.id, mode: .unread),
                isSelected: isSelected,
                isCollapsed: settings.collapsedListIDs.contains(list.id),
                onToggleCollapse: { settings.toggleListCollapsed(list.id) }
            )
            .equatable()
            .tag(Optional(SidebarSelection.list(list.id)))
            .id(SidebarSelection.list(list.id))
            .onTapGesture {
                feedStore.selectedSidebarItem = .list(list.id)
            }
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .contextMenu {
                Button {
                    feedStore.markAllAsRead(for: .list(list.id))
                } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }
                Divider()
                Button(role: .destructive) {
                    feedStore.removeList(id: list.id)
                } label: {
                    Label("Delete List", systemImage: "trash")
                }
            }

            if !settings.collapsedListIDs.contains(list.id) {
                ForEach(visibleFeeds(in: list)) { feed in
                    feedRow(feed)
                }
            }
        }
    }

    @ViewBuilder
    private func categorySection(_ category: String) -> some View {
        Section {
            let categorySelected = feedStore.selectedSidebarItem == .category(category)
            CategoryHeader(
                category: category,
                unreadCount: categoryUnreadCount(category),
                isSelected: categorySelected,
                isCollapsed: settings.collapsedCategories.contains(category),
                onToggleCollapse: { settings.toggleCategoryCollapsed(category) }
            )
            .equatable()
            .tag(Optional(SidebarSelection.category(category)))
            .id(SidebarSelection.category(category))
            .onTapGesture {
                feedStore.selectedSidebarItem = .category(category)
            }
            .listRowBackground(categorySelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .contextMenu {
                Button {
                    feedStore.markAllAsRead(for: .category(category))
                } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }
            }

            if !settings.collapsedCategories.contains(category) {
                ForEach(visibleFeeds(in: category)) { feed in
                    feedRow(feed)
                }
            }
        }
    }

    @ViewBuilder
    private func feedRow(_ feed: Feed) -> some View {
        let isSelected = feedStore.selectedSidebarItem == .feed(feed.id)
        FeedRow(
            feed: feed,
            unreadCount: feedStore.feedBadgeCount(for: feed.id, mode: .unread),
            isSelected: isSelected
        )
        .equatable()
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

    private func openSidebarOrderEditor() {
        settings.sidebarSortMode = .custom
        showingSidebarOrderEditor = true
    }
}

// MARK: - Category Sorting

/// Helpers for applying the user-defined custom category order. Lifted to file
/// scope so MasonryCardsView (cards/newspaper layout) can share the same logic.
enum CategorySorting {
    /// Categories listed in `order` come first in their listed sequence; the rest
    /// fall through to alphabetical. Ensures newly-discovered categories don't
    /// vanish just because the user hasn't ranked them yet.
    static func applyCustom(order: [String], to categories: [String]) -> [String] {
        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return categories.sorted { a, b in
            switch (orderIndex[a], orderIndex[b]) {
            case let (lhs?, rhs?): return lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a < b
            }
        }
    }

    static func applyCustomSidebarOrder(
        order: [SidebarCustomOrderItem],
        to items: [SidebarCustomOrderItem]
    ) -> [SidebarCustomOrderItem] {
        let available = Set(items)
        let saved = order.filter { available.contains($0) }
        let savedSet = Set(saved)
        return saved + items.filter { !savedSet.contains($0) }
    }
}

// MARK: - Sidebar Order Editor

private struct SidebarOrderSheet: View {
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    let allCategoryNames: [String]
    @State private var selectedItemID: String?

    private var orderedCategories: [String] {
        CategorySorting.applyCustom(order: settings.customCategoryOrder, to: allCategoryNames)
    }

    private var defaultOrder: [SidebarCustomOrderItem] {
        feedStore.lists.map { SidebarCustomOrderItem.list($0.id) }
            + orderedCategories.map { SidebarCustomOrderItem.category($0) }
    }

    private var orderedItems: [SidebarCustomOrderItem] {
        CategorySorting.applyCustomSidebarOrder(
            order: settings.customSidebarItemOrder,
            to: defaultOrder
        )
    }

    private var rowItems: [SidebarOrderItem] {
        orderedItems.compactMap { item in
            switch item.kind {
            case .list:
                guard let id = UUID(uuidString: item.value),
                      let list = feedStore.lists.first(where: { $0.id == id }) else { return nil }
                return SidebarOrderItem(
                    id: item.id,
                    title: list.name,
                    subtitle: list.feedIDs.isEmpty ? "No feeds" : "\(list.feedIDs.count) feeds",
                    systemImage: "list.bullet"
                )
            case .category:
                guard allCategoryNames.contains(item.value) else { return nil }
                let count = categoryFeedCount(item.value)
                return SidebarOrderItem(
                    id: item.id,
                    title: item.value,
                    subtitle: count == 1 ? "1 feed" : "\(count) feeds",
                    systemImage: "folder"
                )
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Sidebar Order")
                    .font(.headline)

                Spacer()

                SidebarIconButton(systemName: "arrow.up", tooltip: "Move Up") {
                    moveSelection(by: -1)
                }
                .disabled(!canMoveSelectionUp)

                SidebarIconButton(systemName: "arrow.down", tooltip: "Move Down") {
                    moveSelection(by: 1)
                }
                .disabled(!canMoveSelectionDown)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            if rowItems.isEmpty {
                ContentUnavailableView(
                    "No Custom Items",
                    systemImage: "list.bullet"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SidebarOrderTable(
                    items: rowItems,
                    selectedID: $selectedItemID,
                    onMove: moveItem
                )
            }
        }
        .frame(width: 520, height: 520)
        .onAppear {
            settings.sidebarSortMode = .custom
            normalizeOrder()
        }
    }

    private var canMoveSelectionUp: Bool {
        guard let selectedItemID,
              let index = rowItems.firstIndex(where: { $0.id == selectedItemID }) else { return false }
        return index > 0
    }

    private var canMoveSelectionDown: Bool {
        guard let selectedItemID,
              let index = rowItems.firstIndex(where: { $0.id == selectedItemID }) else { return false }
        return index < rowItems.count - 1
    }

    private func moveSelection(by delta: Int) {
        guard let selectedItemID,
              let sourceIndex = rowItems.firstIndex(where: { $0.id == selectedItemID }) else { return }
        let destination = min(max(sourceIndex + delta, 0), rowItems.count - 1)
        moveItem(id: selectedItemID, to: destination)
    }

    private func moveItem(id: String, to destination: Int) {
        withAnimation(.snappy(duration: 0.18)) {
            var order = orderedItems
            guard let sourceIndex = order.firstIndex(where: { $0.id == id }) else { return }
            let item = order.remove(at: sourceIndex)
            let targetIndex = min(max(destination, 0), order.count)
            order.insert(item, at: targetIndex)
            persist(order)
            selectedItemID = id
        }
    }

    private func normalizeOrder() {
        persist(orderedItems)
    }

    private func categoryFeedCount(_ category: String) -> Int {
        feedStore.feeds.filter { ($0.category ?? "Other") == category }.count
    }

    private func persist(_ order: [SidebarCustomOrderItem]) {
        settings.customSidebarItemOrder = order
        settings.customCategoryOrder = order.compactMap { item in
            item.kind == .category ? item.value : nil
        }
        feedStore.reorderLists(matching: order.compactMap { item in
            guard item.kind == .list else { return nil }
            return UUID(uuidString: item.value)
        })
    }
}

private struct SidebarOrderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
}

private struct SidebarOrderTable: NSViewRepresentable {
    let items: [SidebarOrderItem]
    @Binding var selectedID: String?
    let onMove: (String, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.draggingDestinationFeedbackStyle = .none
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.registerForDraggedTypes([.newsAppSidebarOrderItem])

        let column = NSTableColumn(identifier: .newsAppSidebarOrderColumn)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        tableView.tableColumns.first?.width = max(scrollView.contentView.bounds.width, 100)
        tableView.reloadData()
        context.coordinator.syncSelection(in: tableView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: SidebarOrderTable
        weak var tableView: NSTableView?
        private var dropRow: Int?

        init(parent: SidebarOrderTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.items.count + (dropRow == nil ? 0 : 1)
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if isDropGapRow(row) { return 16 }
            return 44
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            if isDropGapRow(row) {
                let cell = tableView.makeView(
                    withIdentifier: .newsAppSidebarOrderGapCell,
                    owner: self
                ) as? SidebarOrderGapCell ?? SidebarOrderGapCell()
                cell.identifier = .newsAppSidebarOrderGapCell
                return cell
            }

            guard let itemIndex = itemIndex(forDisplayRow: row),
                  parent.items.indices.contains(itemIndex) else { return nil }
            let cell = tableView.makeView(
                withIdentifier: .newsAppSidebarOrderCell,
                owner: self
            ) as? SidebarOrderTableCell ?? SidebarOrderTableCell()
            cell.identifier = .newsAppSidebarOrderCell
            cell.configure(with: parent.items[itemIndex])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            let row = tableView.selectedRow
            let selected = itemIndex(forDisplayRow: row).flatMap { index in
                parent.items.indices.contains(index) ? parent.items[index].id : nil
            }
            if parent.selectedID != selected {
                parent.selectedID = selected
            }
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard let itemIndex = itemIndex(forDisplayRow: row),
                  parent.items.indices.contains(itemIndex) else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(parent.items[itemIndex].id, forType: .newsAppSidebarOrderItem)
            return pasteboardItem
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            clearDropGap(in: tableView)
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            clearDropGap(in: tableView)
            syncSelection(in: tableView)
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            let proposedRow = insertionRow(fromDisplayRow: row)
            guard let draggedID = draggedItemID(from: info),
                  let sourceIndex = parent.items.firstIndex(where: { $0.id == draggedID }),
                  proposedRow != sourceIndex,
                  proposedRow != sourceIndex + 1 else {
                clearDropGap(in: tableView)
                return []
            }
            showDropGap(at: proposedRow, in: tableView)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let proposedRow = insertionRow(fromDisplayRow: row)
            guard let draggedID = draggedItemID(from: info),
                  let sourceIndex = parent.items.firstIndex(where: { $0.id == draggedID }) else {
                clearDropGap(in: tableView)
                return false
            }
            let destination = sourceIndex < proposedRow ? proposedRow - 1 : proposedRow
            guard destination != sourceIndex else {
                clearDropGap(in: tableView)
                return false
            }
            clearDropGap(in: tableView)
            parent.onMove(draggedID, destination)
            parent.selectedID = draggedID
            return true
        }

        func syncSelection(in tableView: NSTableView) {
            guard let selectedID = parent.selectedID,
                  let itemIndex = parent.items.firstIndex(where: { $0.id == selectedID }) else {
                tableView.deselectAll(nil)
                return
            }

            let displayRow = displayRow(forItemAt: itemIndex)
            if tableView.selectedRow != displayRow {
                tableView.selectRowIndexes(IndexSet(integer: displayRow), byExtendingSelection: false)
                tableView.scrollRowToVisible(displayRow)
            }
        }

        private func showDropGap(at row: Int, in tableView: NSTableView) {
            let boundedRow = min(max(row, 0), parent.items.count)
            guard dropRow != boundedRow else { return }
            dropRow = boundedRow
            tableView.reloadData()
        }

        private func clearDropGap(in tableView: NSTableView) {
            guard dropRow != nil else { return }
            dropRow = nil
            tableView.reloadData()
        }

        private func isDropGapRow(_ displayRow: Int) -> Bool {
            dropRow == displayRow
        }

        private func displayRow(forItemAt itemIndex: Int) -> Int {
            if let dropRow, itemIndex >= dropRow {
                return itemIndex + 1
            }
            return itemIndex
        }

        private func itemIndex(forDisplayRow displayRow: Int) -> Int? {
            guard displayRow >= 0 else { return nil }
            if let dropRow {
                if displayRow == dropRow { return nil }
                let itemIndex = displayRow > dropRow ? displayRow - 1 : displayRow
                return parent.items.indices.contains(itemIndex) ? itemIndex : nil
            }
            return parent.items.indices.contains(displayRow) ? displayRow : nil
        }

        private func insertionRow(fromDisplayRow displayRow: Int) -> Int {
            var row = min(max(displayRow, 0), parent.items.count + (dropRow == nil ? 0 : 1))
            if let dropRow, row > dropRow {
                row -= 1
            }
            return min(max(row, 0), parent.items.count)
        }

        private func draggedItemID(from info: NSDraggingInfo) -> String? {
            info.draggingPasteboard.string(forType: .newsAppSidebarOrderItem)
        }
    }
}

private final class SidebarOrderTableCell: NSTableCellView {
    private let symbolView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let textStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(with item: SidebarOrderItem) {
        let image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil)
        image?.isTemplate = true
        symbolView.image = image
        titleField.stringValue = item.title
        subtitleField.stringValue = item.subtitle
    }

    private func setup() {
        guard symbolView.superview == nil else { return }

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        symbolView.contentTintColor = .secondaryLabelColor

        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.addArrangedSubview(titleField)
        textStack.addArrangedSubview(subtitleField)

        addSubview(symbolView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 24),
            symbolView.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 8),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class SidebarOrderGapCell: NSTableCellView {
    private let line = NSBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard line.superview == nil else { return }
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        layer?.cornerRadius = 5

        line.translatesAutoresizingMaskIntoConstraints = false
        line.boxType = .custom
        line.borderWidth = 0
        line.fillColor = .controlAccentColor
        line.cornerRadius = 1
        addSubview(line)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 2)
        ])
    }
}

private extension NSPasteboard.PasteboardType {
    static let newsAppSidebarOrderItem = NSPasteboard.PasteboardType("com.hudleyholdings.newsapp.sidebar-order-item")
}

private extension NSUserInterfaceItemIdentifier {
    static let newsAppSidebarOrderColumn = NSUserInterfaceItemIdentifier("newsAppSidebarOrderColumn")
    static let newsAppSidebarOrderCell = NSUserInterfaceItemIdentifier("newsAppSidebarOrderCell")
    static let newsAppSidebarOrderGapCell = NSUserInterfaceItemIdentifier("newsAppSidebarOrderGapCell")
}

// MARK: - Sidebar Control Bar (Filter + Sort + Expand/Collapse)

private struct SidebarControlBar: View {
    @EnvironmentObject private var settings: SettingsStore
    /// Every reorderable group currently present in the sidebar. The expand/collapse
    /// chip should treat user lists and categories the same way.
    let allCategoryNames: [String]
    let userListIDs: [UUID]
    let onCustomizeOrder: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            FilterToggleChip(isOn: $settings.sidebarFilterUnreadOnly)

            SidebarSortMenuButton(
                sortMode: $settings.sidebarSortMode,
                onCustomizeOrder: onCustomizeOrder
            )
            .frame(width: 56, height: 22)

            // Single labeled toggle. While any group is collapsed the chip offers to
            // expand them all; once everything is expanded it flips to "Collapse all".
            let anyCollapsed = !settings.collapsedCategories.intersection(Set(allCategoryNames)).isEmpty
                || !settings.collapsedListIDs.intersection(Set(userListIDs)).isEmpty
            ExpandCollapseChip(anyCollapsed: anyCollapsed) {
                if anyCollapsed {
                    settings.expandAllCategories()
                    settings.expandAllLists()
                } else {
                    settings.collapseAllCategories(allCategoryNames)
                    settings.collapseAllLists(userListIDs)
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
                Text(anyCollapsed ? "Expand" : "Collapse")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
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
                    .foregroundStyle(isOn ? Color.accentColor : .primary)
                Text(isOn ? "Unread Only" : "All Feeds")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
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

private struct SidebarSortMenuButton: NSViewRepresentable {
    @Binding var sortMode: SidebarSortMode
    let onCustomizeOrder: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Sort")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.title = "Sort"
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.button = button
        button.toolTip = "Sort: \(sortMode.label)"
        // Use `labelColor` (a system-managed appearance-aware color) so the
        // glyph and title stay legible against the sidebar in both light and
        // dark mode. Custom-order mode swaps to the accent color as the
        // active-state indicator.
        button.contentTintColor = sortMode == .custom ? NSColor.controlAccentColor : NSColor.labelColor
        button.attributedTitle = NSAttributedString(
            string: "Sort",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
        button.layer?.backgroundColor = (sortMode == .custom
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.labelColor.withAlphaComponent(0.06)
        ).cgColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SidebarSortMenuButton
        weak var button: NSButton?

        init(parent: SidebarSortMenuButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            for mode in SidebarSortMode.allCases {
                let item = NSMenuItem(
                    title: mode.label,
                    action: #selector(selectSortMode(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = mode.rawValue
                item.state = parent.sortMode == mode ? .on : .off
                menu.addItem(item)
            }

            menu.addItem(.separator())

            let customizeItem = NSMenuItem(
                title: "Customize Order...",
                action: #selector(customizeOrder(_:)),
                keyEquivalent: ""
            )
            customizeItem.target = self
            customizeItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
            menu.addItem(customizeItem)

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
        }

        @objc func selectSortMode(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let mode = SidebarSortMode(rawValue: rawValue) else { return }
            parent.sortMode = mode
        }

        @objc func customizeOrder(_ sender: NSMenuItem) {
            parent.sortMode = .custom
            parent.onCustomizeOrder()
        }
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

struct CategoryHeader: View, Equatable {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let category: String
    let unreadCount: Int
    let isSelected: Bool
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void

    /// Like `FeedRow`, this row is on the hot path and must skip body execution when
    /// its displayed values haven't changed. The closure is excluded from equality —
    /// it captures the category name (which is in the equality check) and the
    /// settings store reference, both stable across renders.
    nonisolated static func == (lhs: CategoryHeader, rhs: CategoryHeader) -> Bool {
        lhs.category == rhs.category
            && lhs.unreadCount == rhs.unreadCount
            && lhs.isSelected == rhs.isSelected
            && lhs.isCollapsed == rhs.isCollapsed
    }

    var body: some View {
        let count = unreadCount
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

struct FeedRow: View, Equatable {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let feed: Feed
    let unreadCount: Int
    let isSelected: Bool

    /// Hot path during refresh — sidebar may have hundreds of these. Equatable lets
    /// SwiftUI skip body execution for rows whose displayed values didn't change in
    /// the current update tick. `feedStore` is intentionally NOT observed here so
    /// per-flush invalidations don't propagate through every row.
    nonisolated static func == (lhs: FeedRow, rhs: FeedRow) -> Bool {
        lhs.feed.id == rhs.feed.id
            && lhs.feed.name == rhs.feed.name
            && lhs.feed.iconURL == rhs.feed.iconURL
            && lhs.feed.isEnabled == rhs.feed.isEnabled
            && lhs.unreadCount == rhs.unreadCount
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        let titleColor = SidebarRowColors.title(for: colorScheme)
        HStack(spacing: 8) {
            FeedIconView(iconURL: feed.iconURL, siteURL: feed.siteURL ?? feed.feedURL, fallbackText: feed.name)
            Text(feed.name)
                .font(settings.listFont(size: settings.feedTitleSize, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            SidebarCountBadge(count: unreadCount)
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
